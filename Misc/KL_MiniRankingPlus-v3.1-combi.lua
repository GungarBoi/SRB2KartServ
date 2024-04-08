--MRP
--MiniRank Plus (Combi edition)
--by Callmore

-- This is a special version of MRP
-- that strips out everything but the combi hud.
-- It does however still load the config,
-- in-case people want the hud disabled, or the mod disabled entierley

local FACE_X = 9
local FACE_Y = 92

local hudeditenable = true

local facegfx = {}
local ranknumsgfx = nil
local hilightgfx = nil
local bumpergfx = nil
local nobumpersgfx = nil

local loadedconfig = false

--CONSTANTS
local DT_NORMAL = 0
local DT_COMBI = 1

local FACEWIDTH = 16

local cv_showcombi = CV_RegisterVar{
	name = "mrp_showcombi",
	defaultvalue = "Yes",
	flags = 0,
	PossibleValue = CV_YesNo
}
local cv_forceoffminirank = CV_RegisterVar{
	name = "mrp_forceoffvanillaminirank",
	defaultvalue = "Yes",
	flags = 0,
	PossibleValue = CV_YesNo
}
local cv_forcedisplay = CV_RegisterVar{
	name = "mrp_forcedisplay",
	defaultvalue = "None",
	flags = CV_CALL,
	PossibleValue = {On = 1, None = 0, Off = -1},
	func = function (self)
		if self.value == -1 then
			hud.enable("minirankings")
		elseif self.value == 1 then
			hud.disable("minirankings")
		end
	end
}

--latius wanted this so ayyy
rawset(_G, "minrankplus", {
    enabled = true
})

local function sortfunc(a, b)
	return a[1].kartstuff[k_position] < b[1].kartstuff[k_position]
end

local playersingame = {}
local alreadycombi = {}
local displaypos = 0
local rankcenter = 3
local xanioff = FACE_X

local function hudThink()
	playersingame = {}
	alreadycombi = {}

	if not loadedconfig then
		COM_BufInsertText(consoleplayer, "exec mrp.cfg -silent")
		loadedconfig = true
	end

	local dp = displayplayers[0]

	for p in players.iterate do
		
		if not (p.valid and not p.spectator) then continue end

		-- Combi support
		if not alreadycombi[p] then --skip someone if their parner was already read
			local dt = DT_NORMAL
			if cv_showcombi.value
			and p.combi
			and p.combi.valid
			and p.combi.valid ~= "uwu"
			and p.combi.valid ~= "maybe"
			and not p.combi.spectator then
				--HA
				--YOU WONT TROLL ME WITH ADDING AN MO INSTEAD OF A PLAYER
				dt = DT_COMBI
				alreadycombi[p.combi] = true
			end
			playersingame[#playersingame+1] = {p, dt}
			--so... all player names have to be unike...
		end
	end
	
	if (#playersingame <= 1) and (cv_forcedisplay.value ~= 1) then return end
	
	if server.vir_enabled then return end -- WORLDS EASIEST MOD INTERGRAION
	
	table.sort(playersingame, sortfunc)
	
	displaypos = 0
	for i, k in ipairs(playersingame) do
		if k[1] == dp then
			displaypos = i
			break
		end
	end
	
	rankcenter = 3
	if #playersingame > 5 and G_RaceGametype() then
		rankcenter = min(max(3, displaypos), #playersingame-2)
	end
end

addHook("ThinkFrame", hudThink)


local function drawMinirank(v, p)
	
	if p ~= displayplayers[0] then return end

	--####################
	--###CACHE GRAPHICS###
	--####################
	
	do
		for s in skins.iterate do
			if facegfx[s.name] then continue end
			--print("Caching " .. s.facerank .. " into " .. #s)
			facegfx[s.name] = v.cachePatch(s.facerank)
		end
		
		if not ranknumsgfx then
			ranknumsgfx = {}
			for i = 0, 16 do
				--print("Caching " .. string.format("OPPRNK%02d", i) .. " into " .. i)
				ranknumsgfx[i] = v.cachePatch(string.format("OPPRNK%02d", i))
			end
		end
		
		if not hilightgfx then
			hilightgfx = {}
			for i = 1, 8 do
				--print("Caching K_CHILI" .. i .. " into " .. i)
				hilightgfx[i-1] = v.cachePatch("K_CHILI" .. i)
			end
		end
		
		if not nobumpersgfx then
			nobumpersgfx = v.cachePatch("K_NOBLNS")
		end
		
		if not bumpergfx then
			bumpergfx = {}
			bumpergfx[1] = v.cachePatch("K_BLNA")
			bumpergfx[2] = v.cachePatch("K_BLNB")
		end
	end

	
	if not (minrankplus and minrankplus.enabled) then return end
	
	if (cv_forceoffminirank.value and not (cv_forcedisplay.value == -1)) and hud.enabled("minirankings") then
		hud.disable("minirankings")
	end

	if outrun and outrun.running then return end

	--#########################
	--###GENERATE PLACEMENTS###
	--#########################
	
	--if leveltime < TICRATE*10 then return end
	if (splitscreen) and (cv_forcedisplay.value ~= 1) then return end
	
	--stupid mod compat stuff

	if (#playersingame <= 1) and (cv_forcedisplay.value ~= 1) then return end

	if cv_forcedisplay.value == -1 then return end
	
	if server.vir_enabled then return end -- WORLDS EASIEST MOD INTERGRAION
	
	--####################
	--###DRAW MINI RANK###
	--####################

	
	for i = -2, 2 do
		if playersingame[rankcenter+i] then

			--draw the players icon, and other extra stuff because AYYYY
			local rankplayer = playersingame[rankcenter+i][1]
			
			if not (rankplayer and rankplayer.valid and rankplayer.mo and rankplayer.mo.valid) then continue end
			
			local drawtype = playersingame[rankcenter+i][2]
			local colorized = {rankplayer.mo.skin}
			local skincolor = {rankplayer.mo.color}
			local vflags = V_HUDTRANS|V_SNAPTOLEFT
			local xpos = xanioff
			local ypos = (FACE_Y+(i*18)+(max(0, 5-#playersingame)*9))

			if rankplayer.mo.colorized then
				colorized[1] = TC_RAINBOW
			end

			--calulate combi
			local colormap = {v.getColormap(colorized[1], skincolor[1])}
			local plrs = {rankplayer}
			if drawtype == DT_COMBI
			and rankplayer and rankplayer.valid
			and rankplayer.combi and rankplayer.combi.valid
			and rankplayer.combi.mo and rankplayer.combi.mo.valid then
				plrs[2] = rankplayer.combi
				skincolor[2] = plrs[2].mo.color
				colorized[2] = plrs[2].mo.skin
				if plrs[2].mo.colorized then
					colorized[2] = TC_RAINBOW
				end
				
				colormap[2] = v.getColormap(colorized[2], skincolor[2])
			else
				drawtype = DT_NORMAL
			end

			
			--face
			for i, k in ipairs(plrs) do
				local facexoff = (i-1)*15
				local facevflags = vflags
				v.draw(xpos+facexoff, ypos, facegfx[k.mo.skin], facevflags, colormap[i])

				if k == p then
					v.draw(xpos+facexoff, ypos, hilightgfx[(leveltime / 4) % 8], vflags)
				end
			end

			--draw bumpers
			if hud.enabled("battlerankingsbumpers") then
				for i, k in ipairs(plrs) do
					local itemxoff = (i-1)*20
					if drawtype == DT_COMBI then
						itemxoff = $+15
					end
					
					if G_BattleGametype() and k.kartstuff[k_bumper] > 0 then
						v.draw(xpos+17+itemxoff, ypos, bumpergfx[1], vflags, colormap[i])
						for b = 1, k.kartstuff[k_bumper]-1 do
							v.draw(xpos+(19+(b*5))+itemxoff, ypos, bumpergfx[2], vflags, colormap[i])
						end
					end
				end
			end
			
			--no bumper indicator
			for i, k in ipairs(plrs) do
				local facexoff = (i-1)*15
				if G_BattleGametype() and k.kartstuff[k_bumper] <= 0 then
					v.draw(xpos-4+facexoff, ypos-3, nobumpersgfx, vflags)
				end
			end

			--placement (eh whatever show both anyway!)
			v.draw(xpos-5, ypos+10, ranknumsgfx[min(max(0, rankplayer.kartstuff[k_position]), 16)], vflags)
		end
	end
end
hud.disable("minirankings")
hud.add(drawMinirank, game)