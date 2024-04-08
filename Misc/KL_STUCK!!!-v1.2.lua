//script that detects stuck players (may not cover EVERY case)
//and kills the player to avoid softlocks and rageqspec or ragequit
//written by lighto97

/////// CVARS HELL ///////

CV_RegisterVar({
	name = "stck_active",
	defaultvalue = "On" ,
	flags = CV_NETVAR ,
	PossibleValue = {Off = 0, On = 1} 
})

//TIME WINDOW TO CONSIDER CONSECUTIVE BUMPS
//if the timer is lower than that, reset the bumpcount
CV_RegisterVar({
	name = "stck_bumpdelay",
	defaultvalue = "8" , //TICRATE, so 35 is one second, 8 is the 4th of a second
	flags = CV_NETVAR ,
	PossibleValue = {MIN = 1, MAX = 99999} //do what you want of your life lol
})

//AMMOUNT OF BUMPS NECESSARY TO RESPAWN A PLAYER
CV_RegisterVar({
	name = "stck_bumpmax",
	defaultvalue = "16" , //either this or 20
	flags = CV_NETVAR ,
	PossibleValue = {MIN = 1, MAX = 99999} 
})

//TIME NECESSARY TO RESPAWN WHEN STUCK BETWEEN CEILING AND FLOOR
CV_RegisterVar({
	name = "stck_squishmax",
	defaultvalue = "70" , //TICRATE so 35 is ONE SECOND, default 2 seconds
	flags = CV_NETVAR ,
	PossibleValue = {MIN = 1, MAX = 99999} 
})

//AMMOUNT OF INSTASHIELDS TO BE CONSIDERED EXCESSIVE TO RESPAWN PLAYER
CV_RegisterVar({
	name = "stck_instamax",
	defaultvalue = "14" , //EACH instashield is a half of a second, two, one second, 14 is 8 seconds
	flags = CV_NETVAR ,
	PossibleValue = {MIN = 1, MAX = 99999} 
})

//AMMOUNT OF TIME TO BE CONSIDERED TOO MUCH INSIDE FLOOR/CEILING
CV_RegisterVar({
	name = "stck_floorceilmax",
	defaultvalue = "70" , //TICRATE, one second is 35, default is 70, 2 seconds
	flags = CV_NETVAR ,
	PossibleValue = {MIN = 1, MAX = 99999} 
})

//AMMOUNT OF TIME TO BE CONSIDERED TOO MUCH INSIDE OFFROAD
CV_RegisterVar({
	name = "stck_offtimemax",
	defaultvalue = "175" , //TICRATE, one second is 35, default is 175, 5 seconds
	flags = CV_NETVAR ,
	PossibleValue = {MIN = 1, MAX = 99999} 
})

//DISTANCE TO BE CONSIDERED TOO BIG FROM MAIN ROAD INTO OFFROAD
CV_RegisterVar({
	name = "stck_maxoffdist",
	defaultvalue = "1024" , //INT so, 1, 32, 100, it gets converted into FRACUNIT later
	flags = CV_NETVAR ,
	PossibleValue = {MIN = 1, MAX = 99999} 
})

//TURNS ON/OFF NOTIFICATIONS EXPLAINING YOUR DEATHS ON CONSOLE
CV_RegisterVar({
	name = "stck_deathnotice",
	defaultvalue = "1" , 
	--flags = nil ,
	PossibleValue = {Off = 0, On = 1} 
})

local localvers, localvername = 3, "foxu"
if not (stuck_lua) then
	print("==============================================================")
	print("STUCK!!! script loaded!")
	print("Done by lighto97, please contact if any bugs/conflicts are found!")
	print("Version number : "+localvers)
	print("Version CodeName : "+localvername)
	rawset(_G,"stuck_lua",{}) //henro there
	stuck_lua.ver = localvers
	stuck_lua.name = localvername
elseif stuck_lua and stuck_lua.ver < localvers then
	print("Older STUCK version detected, check your files!!!")
end


// Returns the ceilingz of the XYZ position
//backported from 2.2 cuz kart odesnt have it
local function L_CeilingzAtPos( x,  y,  z,  height)
	local sec = R_PointInSubsector(x, y).sector
	local ceilingz , isfof

	if sec.c_slope then
		ceilingz = P_GetZAt(sec.c_slope, x, y) 
	else
		ceilingz = sec.ceilingheight
	end
	
	if (sec.ffloors)  then
		local rover
		local delta1, delta2, thingtop = 0,0,z + height

		for rover in sec.ffloors() do
			local topheight, bottomheight
			if not(rover.flags & FF_EXISTS) then
				continue
			end

			if not(rover.flags & FF_SOLID) or not(rover.flags & FF_QUICKSAND) or rover.flags & FF_SWIMMABLE then
				continue
			end
			
			if rover.t_slope then 
				topheight = P_GetZAt(rover.t_slope, x, y) 
			else
				topheight = rover.topheight
			end

			if rover.b_slope then
				bottomheight = P_GetZAt(rover.b_slope, x, y)
			else
				bottomheight = rover.bottomheight
			end

		    --topheight    = P_GetFFloorTopZAt   (rover, x, y)
			--bottomheight = P_GetFFloorBottomZAt(rover, x, y)

			if (rover.flags & FF_QUICKSAND) then
				if (thingtop > bottomheight and topheight > z) then

					if (ceilingz > thingtop) then
						ceilingz = thingtop
					end
				end
				continue
			end

			delta1 = z - (bottomheight + ((topheight - bottomheight)/2))
			delta2 = thingtop - (bottomheight + ((topheight - bottomheight)/2))
			if (bottomheight < ceilingz and abs(delta1) > abs(delta2)) then
				ceilingz = bottomheight
				isfof = rover
			end
		end
	end

	return ceilingz, isfof
end




/////TRAPPED IN A TIGHT SPOT///////
local function stck_checkbump(p)
	local time, bumpmax= CV_FindVar("stck_bumpdelay").value, CV_FindVar("stck_bumpmax").value
	//the following is to detect a player stuck in a tight spot 
	//that they cant get out because they keep bumping a all or something
	//is easy, if theyre been bumping in a small time window
	//and did it few times, theyre stuck
	//if p.kartstuff[k_justbumped]
	if  p.mo.eflags & MFE_JUSTBOUNCEDWALL --YES this flags exists
	and not (
	   p.kartstuff[k_sneakertimer] //ignores wall boost ramming
	or p.kartstuff[k_driftboost]
	or p.kartstuff[k_startboost] ) then 
		p.stck_lastbumptimer = time  //cooldown
		p.stck_bumpammount = $ + 1
	end
	
	//if havent bounced in the defined time, reset
	if p.stck_lastbumptimer <= 0 then
		p.stck_bumpammount = 0	
		p.stck_lastbumptimer = 0
	end
	
	//now does something about they bumping constantly
	if p.stck_bumpammount > bumpmax then
		p.stck_bumpammount = 0	
		p.stck_lastbumptimer = 0
		return true
	elseif p.stck_lastbumptimer <= 0 then
		return false
	end
	p.stck_lastbumptimer = max($ -1,0) 
	return false
end



//////TRAPPED BETWEEN CEILING AND FLOOR/////
local function stck_ceilfloortraped(p)
	//detect when a player get stuck between the ceiling and the floor
	//basically, squished
	//"why dont you use k_squishedtimer instead??"
	//because you could be squished by other things and it would count
	//like by a big player or a mod using this to squish the player
	
	
	//checks height of the ceiling and if there is a fof, its bottom
	//account for slopes
	//aaalso gravflip
	local ceiltop,squishlimit
	squishlimit = CV_FindVar("stck_squishmax").value
	if not (p.mo.eflags & MFE_VERTICALFLIP) then
		ceiltop = L_CeilingzAtPos(p.mo.x, p.mo.y, p.mo.z, p.mo.height)
	else
		ceiltop = P_FloorzAtPos(p.mo.x,p.mo.y,p.mo.z,p.mo.height)
	end
	
	//check for solid fofs too1
	
	//compare the difference, if is lwoer than player height
	//theyre stuck, 100% sure
	if not (p.mo.eflags & MFE_VERTICALFLIP) then
		if p.mo
		and P_IsObjectOnGround(p.mo)
		and  abs(ceiltop - (p.mo.z+p.mo.height)) <=
		p.mo.height then			
			p.stck_timesquished = $ + 1
		else
			p.stck_timesquished = 0
		end
		
	else		
		if p.mo
		and P_IsObjectOnGround(p.mo)
		and  abs(ceiltop - p.mo.z) <=
		p.mo.height then				
			p.stck_timesquished = $ + 1
		else
			p.stck_timesquished = 0
		end
	end
	
	
	//if they spent too much time stuck in this scenario
	//they probably inside somehwere they shouldnt be
	//crushers takes only frames to crush and raise again
	//moving fofs arent this slow, if they stuck by one is faster to respawn 
	
	if p.stck_timesquished >= squishlimit then 
		
		p.stck_timesquished = 0
		return true
	else
		return false
	end
	return false
end

////////////INSTASHIELDING//////////////
local function stck_isntashield(p)
	//if a player  instashields, it means theyre in flashtics 
	//and something tried to hurt them
	//when this happens constantly
	//it means that theyre either staying on a hazard (or taking long to get out of it)
	//or theyre stuck somewhere
	//in some cases they may get stuck in damaging sectors because of damage and offroad
	//best to just die in this scenario too
	
	//a player can do two instashields per second
	//so lets supposed that they get stuck somehwere for four seconds
	//if you inmstashield right after another one, pay attention to it
	//you can do it 4 times, in the 5th youll have some time not doing it
	//because of flashing tics
	//account for this as well
	local isntamax = CV_FindVar("stck_instamax").value
	if p.kartstuff[k_instashield] == 14
	and p.stck_lastinstatimer > 0 then //keep checking after you started instashielding
		//if it only took few frames to instashield again
		//youre being damaged constantly
		p.stck_instaammount = $ + 1
		p.stck_lastinstatimer = 40
		p.kartstuff[k_instashield] = $ - 1
	elseif p.kartstuff[k_instashield] == 14
	and p.stck_lastinstatimer == 0 then 
		//if not, reset
		p.stck_instaammount = 0
		p.stck_lastinstatimer = 0
	end
	
	//to start off the checkings
	if p.kartstuff[k_instashield] == 14
	and p.stck_lastinstatimer == 0 then --not sure if  game wont decrement one before lua can access it
		//it lasts 15 frames (TICRATE is 35, then is half of a second)
		p.stck_instaammount = $ + 1
		p.stck_lastinstatimer = 40 //then set the cooldown, very arbitrary as this wont change much
	end
	p.stck_lastinstatimer = max(($ or 1)-1,0)
	
	//they instashield'ed 14 times in a row
	//yes theyre stuck somewhere
	//but lets check if theyre REALLY stuck
	if p.stck_instaammount >= isntamax then
		local oldpos = {x=p.mo.x,y=p.mo.y,z=p.mo.z}
		//check if your position is valid || per say, sometimes is kiiiinda weird
		if not P_CheckPosition(p.mo,p.mo.x,p.mo.y,p.mo.z) then
			//you shouldnt be there
			p.stck_instaammount = 0
			return true
		elseif not P_TryMove(p.mo,
							 p.mo.x+P_ReturnThrustX(nil,p.mo.angle,p.mo.radius/2),
							 p.mo.y+P_ReturnThrustY(nil,p.mo.angle,p.mo.radius/2),false) then
			//they CANT MOVE
			//many reasons for this
			//1 when stuck in walls or floor, they cant move ( but this wont work for the later)
			//2 when theyre stuck they can speed up but not move
			//3 if they ever move, it will be juuuust a little (specially when inside poly objects)
			p.stck_instaammount = 0
			return true
		else
			//undo the trymove if its valid
			P_MoveOrigin(p.mo,oldpos.x,oldpos.y,oldpos.z)
			return false
		end
	end	
	return false	

end

////////INSIDE FLOOR OR INSIDE CEILING////////////////
local function stck_insidefloororceiling(p)
	if p.mo.flags & MF_NOCLIP
	or p.mo.flags & MF_NOCLIPHEIGHT then return false end
	
	//checks if your bottom or head is inside the floor/ceiling
	//and if its more than half of your height
	//if theyre suppsoed to be there, do nothing
	//probably this wont work well for thin fofs (players may pass through)
	local floorz, ceilingz, floordiff, ceildiff, timermax
	timermax = CV_FindVar("stck_floorceilmax").value
	
	floorz = P_FloorzAtPos(p.mo.x,p.mo.y,p.mo.z,p.mo.height)
	ceilingz = L_CeilingzAtPos(p.mo.x,p.mo.y,p.mo.z,p.mo.height)
	floordiff = abs(p.mo.z - floorz)	
	ceildiff = abs(p.mo.z - ceilingz)	
	
	//if im correct, this dont need to worry about gravflip
	//because the bottom of your characters shouldnt be inside floor
	//neither the top of your character in the ceiling
	//z is ALWAYS the same point
	if ((p.mo.z - floorz < 0
	and floordiff >= p.mo.height / 3)
	or (ceilingz - (p.mo.z+p.mo.height) < 0
	and ceildiff >= p.mo.height / 3)) then
		p.stck_insidefloorceiltimer = $ + 1
	else
		p.stck_insidefloorceiltimer = 0
	end
	
	//theyre stuck there for 4 seconds
	//better to kill them so they can repsawn
	//MONSTER MONARCH SLOPE BUG IS NO MORE :CRABDANCE:
	if p.stck_insidefloorceiltimer >= timermax then
		p.stck_insidefloorceiltimer = 0
		return true
	end
	return false
end

///////////////INSIDE DEEP OFFROAD OR TOO MUCH TIME INTO OFF ROAD///////////////////////
local function checkinsidedeepoffroad(p)
	//sometimes a pleyr can get bumped into offroad
	//while or not in spinout state
	//causing it to drive back to the road
	//slowly for seconds, getting behind everyone
	
	//this functions checks two possibilitites
	//your distance from the road
	//and the time youre into offeoad
	
	
	local maxdist,maxofftime, ks = GetSecSpecial(p.mo.subsector.sector.special,1)
	
	maxdist = CV_FindVar("stck_maxoffdist").value * mapobjectscale
	ks = 4-(CV_FindVar("kartspeed").value +1)
	maxdist = ($ / ks) / (p.kartstuff[k_spinouttype]+1) // easy speed and normal uses lower values
	//distance to be considered to ofar from the road
	maxofftime = CV_FindVar("stck_offtimemax").value //time to be ocnsiderated execcise into offroad
	
	if P_IsObjectOnGround(p.mo)
	and not p.kartstuff[k_offroad] then // NOT offroad
		p.stck_validroad = {x=p.mo.x,y=p.mo.y}	
		
		p.stck_offroadtimer = 0 //always reset this so it counts for each time you enter offroad
		p.stck_distfromroad = 0 //resets this as well
	else
		p.stck_offroad = {x=nil,y=nil}
	end
	
	
	//now check distance from each point to see if youre too deep into offroad
	//so you can be killed and respawned
	
	if p.kartstuff[k_offroad] then //offroad
		
		if P_IsObjectOnGround(p.mo)
		and (p.kartstuff[k_spinouttimer]
		or p.kartstuff[k_justbumped]) then
			
			p.stck_offroad = {x=p.mo.x,y=p.mo.y}			
		else			
			p.stck_validroad = {x=nil,y=nil}
		end
		
		if P_IsObjectOnGround(p.mo) 
		and p.stck_validroad.x
		and p.stck_offroad.x
		and not p.kartstuff[k_invincibilitytimer] //yopu have offroad immunity
		and not p.kartstuff[k_sneakertimer]
		and not p.kartstuff[k_hyudorotimer] then
			
			p.stck_distfromroad = FixedHypot(p.stck_validroad.x - p.stck_offroad.x,
										     p.stck_validroad.y - p.stck_offroad.y )
		end
		if P_IsObjectOnGround(p.mo)
		and not p.kartstuff[k_spinouttimer]
		and not p.kartstuff[k_justbumped]
		and not p.kartstuff[k_invincibilitytimer] //opu have offroad immunity
		and not p.kartstuff[k_sneakertimer]
		and not p.kartstuff[k_hyudorotimer]
		and p.speed <= 22 * mapobjectscale then //let you lammow it
			p.stck_offroadtimer = $ + 1
		end
	end
	
	//yes youre too deep into offroad
	if p.stck_distfromroad >= maxdist then
		
		p.stck_validroad = {x=nil,y=nil}
		p.stck_offroad = {x=nil,y=nil}
		p.stck_distfromroad = 0
		p.stck_offroadtimer = 0
		return true
	end
	
	//other check, if youre too much time into offroad
	//is always faster to respawn
	if p.stck_offroadtimer >= maxofftime then
		p.stck_offroadtimer = 0
		p.stck_validroad = {x=nil,y=nil}
		p.stck_offroad = {x=nil,y=nil}
		p.stck_distfromroad = 0
		return true		
	end
	return false

end

addHook("ThinkFrame",do
	if not CV_FindVar("stck_active").value then return end
	for p in players.iterate do
		if leveltime == 2 then p.stck_init = nil continue end
		if not p
		or (p and not p.valid)
		or not p.mo
		or (p.mo and not p.mo.valid)
		or p.exiting then continue end
		//first, initiliaze
		local notify = CV_FindVar("stck_deathnotice").value
		if not p.stck_init then
			p.stck_lastbumptimer = 0
			p.stck_bumpammount = 0
			p.stck_timesquished = 0
			p.stck_instaammount = 0
			p.stck_lastinstatimer = 0
			p.stck_insidefloorceiltimer = 0
			p.stck_validroad = {x,y}
			p.stck_offroad = {x,y}
			p.stck_distfromroad = 0
			p.stck_offroadtimer = 0
			p.stck_init = true
		end
		if p.cmd.buttons & BT_ATTACK then
			//DEBUG
			//p.mo.z = $ + 16*FRACUNIT
			//p.kartstuff[k_spinouttimer] = (3*TICRATE/2)+2 --40
			//P_InstaThrust(p.mo,p.mo.angle,p.speed)
		end
		
		//kill you because youre trapped in a tight spot
		if stck_checkbump(p) then
			P_KillMobj(p.mo)
			if notify then
				CONS_Printf(p, "killed for :\x82 getting stuck in a tight spot")
			end
		end
		
		//kil lyou because youre stuck betwen ceiling and floor for too long
		if stck_ceilfloortraped(p) then
			P_KillMobj(p.mo)
			if notify then
				CONS_Printf(p, "killed for :\x82 getting stuck between ceiling and floor for too long")
			end
		end
			
		//kill because you get stuck somehwere and is being damaged constantly
		if stck_isntashield(p) then
			P_KillMobj(p.mo)
			if notify then
				CONS_Printf(p, "killed for :\x82 getting damaged constantly and not being able to move or youre in a valid spot (you shouldn't be there)")
			end
		end
		if stck_insidefloororceiling(p) then
			P_KillMobj(p.mo)
			if notify then
				CONS_Printf(p, "killed for :\x82 getting stuck inside floor/ceiling for too long")
			end
		end
		
		//kill because youre too deep into offroad
		//or too much time on it
		if checkinsidedeepoffroad(p) then
			P_KillMobj(p.mo)
			if notify then
				CONS_Printf(p, "killed for :\x82 Getting trapped into offroad")
			end
		end
	end

end)

//from Chronoshift's kmp interop
addHook("MobjDeath", function(mobj)
	if not CV_FindVar("stck_active").value then return end
	if not (kmp_respawnpoints and kmp_respawnpoints.value) then return end
	
	local player = mobj.player
	if not (mobj and player and not player.spectator) then return end
	
	if player.kmp_respawn then player.kmp_respawn = nil end
end, MT_PLAYER)

-- Prevent the never ending spawning gargoyles from killing the framerate.
addHook("MobjThinker", function(gargoyle)
	if not CV_FindVar("stck_active").value then return end
	if not (kmp_respawnpoints and kmp_respawnpoints.value) then return end
	
	if gargoyle.flags & MF_RUNSPAWNFUNC and gargoyle.flags2 & MF2_DONTDRAW then
		P_RemoveMobj(gargoyle) -- Go away.
	end	
end, MT_GARGOYLE)
