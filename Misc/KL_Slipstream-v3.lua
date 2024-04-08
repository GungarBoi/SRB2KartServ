-- Author: Ashnal
-- Adds slipstreaming aka drafting like the later Mario Kart games
-- Youll see small gray speed lines when you're charging a slipstream boost
-- Theres a subtle woosh sound when it activates, and the gray speed lines will become normal size and more frequent
-- You need to have another racer within the maxangle of your heading, and be within the maxdistiance range to charge it
-- the closer you are to them, the faster it will charge
-- KNOWN BUG: the fast lines have some wierd angles on OpenGL rendering. No idea why.

local cv_slipstream = CV_RegisterVar({
    name = "slipstream_enabled",
    defaultvalue = "On",
    flags = CV_NETVAR,
    PossibleValue = CV_OnOff
})

local cv_colorized = CV_RegisterVar({
    name = "slipstream_colorized",
    defaultvalue = "On",
    flags = NULL,
    PossibleValue = CV_OnOff
})

local cv_reminder = CV_RegisterVar({
    name = "slipstream_reminder",
    defaultvalue = "On",
    flags = NULL,
    PossibleValue = CV_OnOff
})

local cv_maxdistance = CV_RegisterVar({
    name = "slipstream_maxdistance",
    defaultvalue = 1500, -- enough room to charge slowly, and dodge
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

local cv_t2chargedist = CV_RegisterVar({
    name = "slipstream_t2chargedist",
    defaultvalue = 1050,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

local cv_t3chargedist = CV_RegisterVar({
    name = "slipstream_t3chargedist",
    defaultvalue = 400, -- danger close, woudln't be able to dodge an aimed item
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

local cv_maxangle = CV_RegisterVar({
    name = "slipstream_maxangle",
    defaultvalue = ANG1*14,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

-- This is measured in tics
local cv_chargetoboost = CV_RegisterVar({
    name = "slipstream_chargetoboost",
    defaultvalue = 3*TICRATE,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

local cv_boosttime = CV_RegisterVar({
    name = "slipstream_boosttime",
    defaultvalue = 2*TICRATE,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

local cv_minimumspeed = CV_RegisterVar({
    name = "slipstream_minimumspeed",
    defaultvalue = 30,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

-- Boost youll get if you're a 1 kartspeed
local cv_maxspeedboostpercent = CV_RegisterVar({
    name = "slipstream_maxspeedboostpercent",
    defaultvalue = 50,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

-- Boost youll get if you're a 9 or higher kartspeed
local cv_minspeedboostpercent = CV_RegisterVar({
    name = "slipstream_minspeedboostpercent",
    defaultvalue = 25,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

local cv_accelboostpercent = CV_RegisterVar({
    name = "slipstream_accelboostpercent",
    defaultvalue = 10,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

local cv_maxdraftspeedboostpercent = CV_RegisterVar({
    name = "slipstream_maxdraftspeedboostpercent",
    defaultvalue = 15,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})

local cv_mindraftspeedboostpercent = CV_RegisterVar({
    name = "slipstream_mindraftspeedboostpercent",
    defaultvalue = 0,
    flags = CV_NETVAR,
    PossibleValue = CV_Unsigned
})


local soundcooldown = 3*TICRATE
local starttime = 6*TICRATE + (3*TICRATE/4)

local angletotarget = nil
local disttotarget = nil
local slipstreamtarget = nil
local charge = 0
local speedboost = 0
local accelboost = 0
local tier = 0

local function IntPercentToFixed(int)
	return FixedDiv(int*FRACUNIT, 100*FRACUNIT)
end

-- prefer to input all fixed values
-- https://en.wikipedia.org/wiki/Feature_scaling
local function Rescale(value, oldmin, oldmax, newmin, newmax)
	return newmin +  FixedMul(FixedDiv( value-oldmin , oldmax-oldmin), newmax-newmin)
end

local function SpawnFastLines(p, tier, color)
    if p.fastlinestimer == 1 or tier == 1 then
        local fast = P_SpawnMobj(p.mo.x + (P_RandomRange(-36,36) * p.mo.scale),
            p.mo.y + (P_RandomRange(-36,36) * p.mo.scale),
            p.mo.z + (p.mo.height/2) + (P_RandomRange(-20,20) * p.mo.scale),
            MT_FASTLINE)
        fast.angle = R_PointToAngle2(0, 0, p.mo.momx, p.mo.momy)
        fast.momx = 3*p.mo.momx/4
        fast.momy = 3*p.mo.momy/4
        fast.momz = 3*p.mo.momz/4
        fast.color = color
        fast.colorized = true
        K_MatchGenericExtraFlags(fast, p.mo)

        fast.scale = $/tier
        p.fastlinestimer = tier
    end
    p.fastlinestimer = max($-1, 1)
end

local function FSonicRunDust(mo)
	local angle = mo.angle
	local newx
	local newy
	local parts
	local i
	if leveltime%2 then
		for i = 0,1 do
			newx = mo.x + P_ReturnThrustX(mo, angle + ((i == 0) and -1 or 1)*ANGLE_90, FixedMul(16*FRACUNIT, mo.scale))			
			newy = mo.y + P_ReturnThrustY(mo, angle + ((i == 0) and -1 or 1)*ANGLE_90, FixedMul(16*FRACUNIT, mo.scale))
			parts = P_SpawnMobj(newx, newy, (verticalflip and (mo.ceilingz or -1) or mo.floorz), MT_PARTICLE)
			parts.target = mo
			parts.angle = angle - ((i == 0) and -1 or 1)*ANGLE_45
			parts.scale = mo.scale
			parts.destscale = mo.scale*3
			parts.scalespeed = mo.scale/6
			parts.momx = 3*mo.momx/5
			parts.momy = 3*mo.momy/5				
			parts.fuse = 5
		end
	end
end

--hud.add(function(v, p, c)
--    if p.spectator then return end
--    v.drawString(12,145,FixedMul(p.kartstuff[k_speedboost], 100*FRACUNIT)>>FRACBITS,V_SNAPTOLEFT,"left")
--end)

addHook("ThinkFrame", do

    if not cv_slipstream.value then return end -- Has to be turned on

    local mapscale = (mapheaderinfo[gamemap] and mapheaderinfo[gamemap].mobj_scale or FRACUNIT)
    local T3_DISTANCE = cv_t3chargedist.value * mapscale
    local T2_DISTANCE = cv_t2chargedist.value * mapscale
    local MAX_DISTANCE = cv_maxdistance.value * mapscale

    for p in players.iterate do

        if(leveltime == 3*TICRATE and cv_reminder.value) then 
            chatprintf(p, "\131* Don't forget you can \130draft\131 behind another player to charge a \130slipstream speed boost!", true)
        end

        if p.mo then  -- must have valid player mapobject

            if p.kartstuff[k_spinouttimer] and p.kartstuff[k_wipeoutslow] == 1 then -- no slipstreaming if you've bumped or spun out
                p.slipstreamboost = 0
                p.slipstreamcharge = 0
            else

                if p.slipstreamcharge == nil then
                    p.slipstreamcharge = 0
                    p.slipstreamboost = 0
                    p.fastlinestimer = 0
                    p.slipstreamsoundtimer = false
                end

                -- reset until we find a valid slipstreamtarget this frame
                slipstreamtarget = nil
                angletotarget = nil
                disttotarget = nil
                charge = 0
                speedboost = p.kartstuff[k_speedboost]
                accelboost = p.kartstuff[k_accelboost]

                if (P_IsObjectOnGround(p.mo)
                and not p.kartstuff[k_drift]
				and not p.kartstuff[k_hyudorotimer]
                and FixedDiv(p.speed, mapobjectscale)/FRACUNIT >= cv_minimumspeed.value -- must be moving decently on the ground, not drifting
                ) then
                    
                    for potentialtarget in players.iterate do          

                        if (potentialtarget.mo -- must have valid player mapobject
                        and potentialtarget.mo ~= p.mo -- Can't splipstream off yourself
                        and not potentialtarget.kartstuff[k_hyudorotimer] -- or ghosts
                        and P_IsObjectOnGround(potentialtarget.mo) -- or airbourne karts
                        and FixedDiv(potentialtarget.speed, mapobjectscale)/FRACUNIT >= cv_minimumspeed.value -- or slowpokes
                        ) then

                            angletotarget = abs(p.mo.angle - R_PointToAngle2(p.mo.x, p.mo.y, potentialtarget.mo.x, potentialtarget.mo.y))
                            if angletotarget > cv_maxangle.value then continue end -- Narrow angle for following to slipstream
                            disttotarget = P_AproxDistance(p.mo.x - potentialtarget.mo.x, p.mo.y - potentialtarget.mo.y)
                            if disttotarget > MAX_DISTANCE then continue end -- max slipstream distance

                            --  print(p.mo.skin + " " + potentialtarget.mo.skin + " angletotarget: " + angletotarget + " disttotarget: " + disttotarget + " slipstreamtarget: " + p.slipstreamtarget)

                            slipstreamtarget = potentialtarget
                            break

                        end
                    end
                end

                -- add/remove slipstream charge
                if slipstreamtarget then

                    if disttotarget > T2_DISTANCE then
                        charge = 1
                    elseif disttotarget > T3_DISTANCE then
                        charge = 2
                    else
                        charge = 3
                    end

                    p.slipstreamcharge = min($+charge, cv_chargetoboost.value)
                    -- print(p.mo.skin + " " +slipstreamtarget.mo.skin + " angletotarget: " + angletotarget + " disttotarget: " + disttotarget + " charging slipstream: " + p.slipstreamcharge)

                    -- also spawn mini lines if charging to teach/show player the charging area
                    if p.slipstreamboost == 0 then
					
                        SpawnFastLines(p, 2, SKINCOLOR_WHITE)

						local clampedkartspeed = max(min(p.kartspeed, 9), 1)
						local draftingboost = Rescale(clampedkartspeed*FRACUNIT, 9*FRACUNIT, FRACUNIT, IntPercentToFixed(cv_mindraftspeedboostpercent.value), IntPercentToFixed(cv_maxdraftspeedboostpercent.value))
                        speedboost = max(speedboost, draftingboost)
                        p.slipstreamsoundtimer = false
						
                    end

                else
                    -- if p.slipstreamcharge then print(p.mo.skin + " losing  slipstream " + p.slipstreamcharge) end
                    p.slipstreamcharge = max($-1, 0)
                end

                if p.slipstreamcharge >= cv_chargetoboost.value then
				
                    -- print(p.mo.skin + " slipstreaming!")
                    p.slipstreamboost = cv_boosttime.value

                    if p.slipstreamsoundtimer == false then
                        S_StartSoundAtVolume(p.mo, sfx_s3k82, INT32_MAX)
                        p.slipstreamsoundtimer = true
                    end
					
                end

                if p.slipstreamboost then
				
                    local clampedkartspeed = max(min(p.kartspeed, 9), 1)
					local slipstreamspeedboost = Rescale(clampedkartspeed*FRACUNIT, 9*FRACUNIT, FRACUNIT, IntPercentToFixed(cv_minspeedboostpercent.value), IntPercentToFixed(cv_maxspeedboostpercent.value))
					
                    speedboost = max(speedboost, slipstreamspeedboost)
                    accelboost = max(accelboost, IntPercentToFixed(cv_accelboostpercent.value))

					if cv_colorized.value then
						SpawnFastLines(p, 1, p.skincolor)
					else 
						SpawnFastLines(p, 1, SKINCOLOR_WHITE)
					end
                    
                    if P_IsObjectOnGround(p.mo) then
						FSonicRunDust(p.mo)
					end

                end

                -- value smoothing
                if (speedboost > p.kartstuff[k_speedboost]) then
                    p.kartstuff[k_speedboost] = speedboost
                else
                    p.kartstuff[k_speedboost] = p.kartstuff[k_speedboost] + (speedboost - p.kartstuff[k_speedboost])/(TICRATE/2)
                end

                p.kartstuff[k_accelboost] = accelboost

                -- if p.slipstreamboost then print(p.mo.skin + " slipstreamboost: " + p.slipstreamboost) end
                p.slipstreamboost = max($-1, 0)
                --p.slipstreamsoundtimer = max($-1, 0)
            end
        end
    end
end)