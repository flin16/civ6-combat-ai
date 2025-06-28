local function debugTurnInfo(playerID)
	local turn = Game.GetCurrentGameTurn()
	print("Current turn: " .. turn)
	print("Player ID: " .. playerID)
end

local function map(tbl, func)
	local result = {}
	-- Now switched to a universal version
	-- for i, v in ipairs(tbl) do
	for k, v in pairs(tbl) do
		result[k] = func(v)
	end
	return result
end

local function graph(tbl, func)
	local result = {}
	for _, v in pairs(tbl) do
		result[v] = func(v)
	end
	return result
end

local function filter(tbl, func)
	local result = {}
	for k, v in pairs(tbl) do
		if func(v) then
			result[k] = v
		end
	end
	return result
end

local function table_contains(tbl, val)
	for _, v in pairs(tbl) do
		if v == val then
			return true
		end
	end
	return false
end

local function compose(f, g)
	return function(...)
		return f(g(...))
	end
end

local function table_union(ts)
	local result = {}
	if not ts then
		return {}
	end
	for _, t in ipairs(ts) do
		if t then
			for _, v in ipairs(t) do
				table.insert(result, v)
			end
		end
	end
	return result
end

local function unique(t)
	local result = {}
	for _, v in ipairs(t) do
		if not table_contains(result, v) then
			table.insert(result, v)
		end
	end
	return result
end

local function union(...)
	local tables = { ... }
	local result = {}
	for _, tbl in ipairs(tables) do
		for _, v in ipairs(tbl) do
			table.insert(result, v)
		end
	end
	result = unique(result)
	return result
end
local function map_union(tbl, func)
	local results = {}
	for _, v in pairs(tbl) do
		local sub_results = func(v)
		results = union(results, sub_results)
	end
	return results
end

local function subtract(tbl1, tbl2)
	local result = {}
	if not tbl1 then
		return result
	end
	for _, v in ipairs(tbl1) do
		if not table_contains(tbl2, v) then
			table.insert(result, v)
		end
	end
	return result
end

local function min(tb)
	local min_val = math.huge
	local min_arg = nil
	for k, v in pairs(tb) do
		if v < min_val then
			min_val = v
			min_arg = k
		end
	end
	return min_val, min_arg
end

local function max(tb)
	local neg_max_val, max_arg = min(map(tb, function(v)
		return -v
	end))
	return -neg_max_val, max_arg
end

local function print_tb(t)
	for k, v in pairs(t) do
		print(k, v)
	end
end

local function show(t)
	print("Showing table:" .. t)
	for k, row in pairs(t) do
		local x = row:GetX()
		local y = row:GetY()
		local v = row.Value or ""
		if not v and row.GetProperty then
			v = row:GetProperty("Value")
		end
		local c = row.Content or v or "Here"
		print("Plot at (" .. x .. ", " .. y .. ")" .. v)
		UI.AddWorldViewText(0, c, x, y, 0)
	end
end

local aCities = {}
local cityLocs = {}
local enemiesID = {}
local eCities = {}
local eCityLocs = {}
local promoC2T = {}
local hashTable = {}

function GetHashTable()
	local function dump(func_name)
		local tbl = GameInfo[func_name .. "s"]()
		for row in tbl do
			row.MyType = func_name:upper()
			hashTable[row.Hash] = row
		end
	end
	-- Add table names if needed, do not append 's' to the end
	local lists = { "District", "Building", "Unit", "Project", "Civic", "Technologie" }
	for _, item in pairs(lists) do
		dump(item)
	end
end

function Research(player)
	local tech = player:GetTechs()
	if tech and tech:GetResearchingTech() == -1 then
		local rec = player:GetGrandStrategicAI():GetTechRecommendations()
		for _, term in pairs(rec) do
			local hash = term.TechHash
			local index = hashTable[hash].Index
			if not tech:HasTech(index) then
				UI.RequestPlayerOperation(player:GetID(), PlayerOperations.RESEARCH, {
					[PlayerOperations.PARAM_TECH_TYPE] = hash,
				})
				break
			end
		end
	end
	local cult = player:GetCulture()
	if cult and cult:GetProgressingCivic() == -1 then
		local rec = player:GetGrandStrategicAI():GetCivicsRecommendations()
		for _, term in pairs(rec) do
			local hash = term.CivicHash
			local index = hashTable[hash].Index
			if not cult:HasCivic(index) then
				UI.RequestPlayerOperation(player:GetID(), PlayerOperations.PROGRESS_CIVIC, {
					[PlayerOperations.PARAM_CIVIC_TYPE] = hash,
				})
				break
			end
		end
	end
end

--- Return back lowRatio and corresponding Type hash
function CheckLowUnits(player, getType)
	-- TODO: Cache units and avoid use units alive
	local units = GetPlayerUnits(player)
	if not units then
		return
	end
	local distro = {}
	local cnt = 0
	for _, unit in pairs(units) do
		local type = getType(unit)
		if not distro[type] then
			distro[type] = 0
		end
		distro[type] = distro[type] + 1
		cnt = cnt + 1
	end
	local lowCount, lowType = min(distro)
	for _, unit in pairs(units) do
		if getType(unit) == lowType then
			lowType = GameInfo.Units[unit:GetUnitType()].Hash
			break
		end
	end
	for k, v in pairs(distro) do
		distro[k] = v / cnt
	end
	return lowCount / cnt, lowType
end

function CityBuild(city)
	if city:GetBuildQueue():GetSize() > 0 then
		return false, nil
	end
	-- TODO: make it smarter
	local function classifier(unit)
		local row
		if type(unit) ~= "number" then
			row = GameInfo.Units[unit:GetUnitType()]
		else
			row = hashTable[unit]
		end
		return row.Name
		-- local kinds = { "Combat", "RangedCombat", "Bombard" }
		-- local params = {}
		-- for _, kind in pairs(kinds) do
		-- 	params[kind] = row[kind] or 0
		-- end
		-- local _, maxArg = max(params)
		-- return maxArg
	end
	local cityAI = city:GetCityAI()
	local rec = cityAI:GetBuildRecommendations()
	local lowRatio, lowHash = CheckLowUnits(Players[city:GetOwner()], classifier)
	if lowRatio < 0.15 then
		table.insert(rec, { BuildItemHash = lowHash, BuildItemScore = math.huge })
	end
	table.sort(rec, function(a, b)
		return a.BuildItemScore > b.BuildItemScore
	end)
	for k, v in pairs(rec) do
		local hash = v.BuildItemHash
		local row = hashTable[hash]
		local objectType = row.MyType
		local paramName = "PARAM_" .. objectType:upper() .. "_TYPE"
		local paramKey = CityOperationTypes[paramName]
		local tParameters = {
			[paramKey] = hash,
		}
		local canStartOperation = function()
			return CityManager.CanStartOperation(city, CityOperationTypes.BUILD, tParameters, true)
		end
		local request = function()
			return CityManager.RequestOperation(city, CityOperationTypes.BUILD, tParameters)
		end
		local canStart, results = canStartOperation()
		results = results or {}
		if canStart then
			if objectType == ("District"):upper() then
				local plots = Index2Plots(results[CityOperationResults.PLOTS] or {})
				for _, plot in pairs(plots) do
					tParameters[CityOperationTypes.PARAM_X] = plot:GetX()
					tParameters[CityOperationTypes.PARAM_Y] = plot:GetY()
					if canStartOperation() then
						request()
						break
					end
				end
			elseif objectType == ("Unit"):upper() then
				local formTypes = { "Army", "Corps" }
				local canForm = false
				for _, form in pairs(formTypes) do
					canForm = results[CityOperationResults["CAN_TRAIN_" .. form:upper()]] or false
					if canForm then
						tParameters[CityOperationTypes.MILITARY_FORMATION_TYPE] =
							MilitaryFormationTypes[form:upper() .. "_MILITARY_FORMATION"]
						request()
						break
					end
				end
				if not canForm then
					request()
				end
			else
				request()
			end
			return true, row
		end
	end
	return false, nil
end

function GetPromotionTable()
	for row in GameInfo.UnitPromotions() do
		if not promoC2T[row.PromotionClass] then
			promoC2T[row.PromotionClass] = {}
		end
		table.insert(promoC2T[row.PromotionClass], row.Index)
	end
end

function Promote(unit)
	print("Promoting unit:", unit:GetID(), "at", unit:GetX(), unit:GetY())
	local unitType = unit:GetUnitType()
	local unitInfo = GameInfo.Units[unitType]
	local promoClass = unitInfo.PromotionClass
	for _, type in pairs(promoC2T[promoClass]) do
		local tParameters = {
			[UnitCommandTypes.PARAM_PROMOTION_TYPE] = type,
		}
		if UnitManager.CanStartCommand(unit, UnitCommandTypes.PROMOTE, tParameters) then
			UnitManager.RequestCommand(unit, UnitCommandTypes.PROMOTE, tParameters)
			return type
		end
	end
end

function DistrictAttack(district)
	if not CityManager.CanStartCommand(district, CityCommandTypes.RANGE_ATTACK) then
		return
	end
	for _, target in pairs(GetRangeAttackTargets(district)) do
		local tParameters = {
			[CityCommandTypes.PARAM_X] = target:GetX(),
			[CityCommandTypes.PARAM_Y] = target:GetY(),
		}
		if CityManager.CanStartCommand(district, CityCommandTypes.RANGE_ATTACK, tParameters) then
			CityManager.RequestCommand(district, CityCommandTypes.RANGE_ATTACK, tParameters)
		end
	end
end
local function IsAir(unit)
	return GameInfo.Units[unit:GetUnitType()].Domain == "DOMAIN_AIR"
end
function UnitRangeAttack(unit)
	local air = IsAir(unit)
	local prefix = "RANGE"
	if air then
		prefix = "AIR"
	end
	local attack_name = prefix .. "_ATTACK"
	for _, plot in pairs(GetRangeAttackTargets(unit, air)) do
		if plot then
			local tParameters = {
				[UnitOperationTypes.PARAM_X] = plot:GetX(),
				[UnitOperationTypes.PARAM_Y] = plot:GetY(),
			}
			if air then
				tParameters[UnitOperationTypes.PARAM_MODIFIERS] = UnitOperationMoveModifiers.ATTACK
			end
			if UnitManager.CanStartOperation(unit, UnitOperationTypes[attack_name], nil, tParameters) then
				UnitManager.RequestOperation(unit, UnitOperationTypes[attack_name], tParameters)
				return true
			end
		end
	end
	return false
end

local playerZone = {}
local enemyZone = {}
local front = {}

GetPromotionTable()
GetHashTable()
function OnPlayerTurnActivated(playerID)
	local player = GetLocalPlayer(playerID)
	if not player then
		return
	end
	debugTurnInfo(playerID)
	-- first find enemy ids
	enemiesID = map(GetEnemies(player), function(e)
		return e:GetID()
	end)
	Research(player)
	front = GetFrontier(player)
	GetCities(true)
	ShowEval(player)
	local strengthDiff = GetStrengthDiff(player)
	for _, city in player:GetCities():Members() do
		CityBuild(city)
		DistrictAttack(city)
		for _, district in city:GetDistricts():Members() do
			DistrictAttack(district)
		end
	end
	for _, unit in player:GetUnits():Members() do
		local exp = unit:GetExperience()
		local expToNext = exp:GetExperienceForNextLevel()
		local expNow = exp:GetExperiencePoints()
		if expNow >= expToNext then
			Promote(unit)
		elseif IsAir(unit) then
			if UnitHealthy(unit) then
				UnitRangeAttack(unit)
			end
		--TODO: overhaul logic
		-- elseif unit:GetRange() > 0 then
		-- elseif unit:GetCombat() > 0 then
		-- end
		else
			local attacked = false
			if not UnitHealthy(unit) and Distance2Plots(unit, front) < 5 then
				Escape(unit)
			elseif unit:GetRange() > 0 then
				attacked = UnitRangeAttack(unit)
				if not attacked then
					if strengthDiff > 5 then
						Rush(unit, 0)
					else
						Rush(unit, 1)
					end
				end
			elseif unit:GetCombat() > 0 then
				local ePlots = GetMeleeTargets(unit)
				if not ePlots then
					break
				end
				local target = nil
				for _, ePlot in pairs(ePlots) do
					local res = CombatManager.SimulateAttackVersus(unit:GetComponentID(), ePlot:GetComponentID()) or {}
					local attRes = res[CombatResultParameters.ATTACKER] or {}
					local cost = attRes[CombatResultParameters.DAMAGE_TO]
					if cost then
						if ePlot:GetRange() > 0 then
							local isCity = table_contains(cityLocs, Map.GetPlotIndex(ePlot:GetX(), ePlot:GetY()))
							if not isCity then
								cost = cost - 10
							end
						end
						if cost < 25 then
							target = ePlot
							break
						end
					end
				end
				if target then
					MeleeAttackPlot(unit, target)
					attacked = true
				end
				if not attacked then
					local lowBound = 0
					if strengthDiff > 5.0 then
						lowBound = -1
					end
					if not Rush(unit, lowBound) then
						UnitFortify(unit)
					end
				end
			end
		end
	end
end

function ShowEval(player)
	local eval = EvalMap(player)
	local cnt = 0
	for _, _ in pairs(eval) do
		cnt = cnt + 1
	end
	for index, grade in pairs(eval) do
		local plot = Map.GetPlotByIndex(index)
		if plot then
			local x = plot:GetX()
			local y = plot:GetY()
			print("Plot index:", index, "at", x, y, "Grade:", grade)
			if grade then
				UI.AddWorldViewText(0, tostring(grade), x, y, 0)
			end
		end
	end
end

-- TODO: make this a frontier system
function EvalMap(player)
	local tot = {}
	local function grader(objs, func)
		for _, obj in pairs(objs) do
			local plots, grades = func(obj)
			for _, plot in pairs(plots) do
				local index = plot:GetIndex()
				if index then
					if not tot[index] then
						tot[index] = 0
					end
					tot[index] = tot[index] + (grades[index] or 0)
				end
			end
		end
	end
	local function limitN(n)
		return function(u, t)
			local dist = Distance2Plots(u, { t })
			if dist < n then
				return (n - dist) / n
			end
		end
	end
	local neg = function(r)
		if not r then
			return false
		end
		return -r
	end
	local const = function(n)
		return function(_)
			return n
		end
	end
	local function eval_wraper(func)
		return function(p)
			return { p }, { [p:GetIndex()] = func(p) }
		end
	end
	local playerID = player:GetID()
	local pCities = filter(aCities, function(c)
		return playerID == c:GetOwner()
	end)
	grader(pCities, function(city)
		return DfsManager(city, limitN(4))
	end)
	grader(eCities, function(city)
		return DfsManager(city, compose(neg, limitN(5)))
	end)
	local pDomain = GetOwnedPlots(player)
	local eDomain = map_union(GetEnemies(player), function(e)
		return GetOwnedPlots(e)
	end)
	grader(pDomain, eval_wraper(const(1.5)))
	grader(eDomain, eval_wraper(const(-1.5)))
	local pUnits = GetPlayerUnits(player)
	local eUnits = GetEnemyUnits(player)
	grader(pUnits, function(unit)
		return DfsManager(unit, limitN(2))
	end)
	grader(eUnits, function(unit)
		return DfsManager(unit, compose(neg, limitN(2)))
	end)
	return tot
end

function UnitHealthy(pUnit)
	return pUnit:GetDamage() < pUnit:GetMaxDamage() * 0.3
end
function UnitFortify(pUnit)
	local tParameters = {}
	if UnitManager.CanStartOperation(pUnit, UnitOperationTypes.FORTIFY, nil, tParameters) then
		UnitManager.RequestOperation(pUnit, UnitOperationTypes.FORTIFY, tParameters)
	end
end

function Turn2Plots(unit, plots)
	if plots.GetX then
		plots = { plots }
	end
	local mTurn = math.huge
	for _, plot in pairs(plots) do
		if unit:GetX() == plot:GetX() and unit:GetY() == plot:GetY() then
			return 0
		end
		local _, turnList = UnitManager.GetMoveToPath(unit, plot:GetIndex())
		local n = #turnList
		if n > 0 then
			local turnCount = turnList[n]
			if turnCount < mTurn then
				mTurn = turnCount
			end
		end
	end
	return mTurn
end

function Distance2Plots(unit, plots)
	-- also appies to the case when unit is actually a plot
	local minD = 1289
	local dist
	for i, p in ipairs(plots) do
		dist = Map.GetPlotDistance(unit:GetX(), unit:GetY(), p:GetX(), p:GetY())
		if dist < minD then
			minD = dist
		end
	end
	return minD
end

function TotalDistance2Plots(unit, plots)
	local total = 0
	for _, p in pairs(plots) do
		total = total + Map.GetPlotDistance(unit:GetX(), unit:GetY(), p:GetX(), p:GetY())
	end
	return total
end

function Move2Plot(unit, plot, try)
	local tParameters = {
		[UnitOperationTypes.PARAM_X] = plot:GetX(),
		[UnitOperationTypes.PARAM_Y] = plot:GetY(),
	}
	tParameters[UnitOperationTypes.PARAM_MODIFIERS] = UnitOperationMoveModifiers.NONE
	if UnitManager.CanStartOperation(unit, UnitOperationTypes.MOVE_TO, nil, tParameters) then
		if not try then
			UnitManager.RequestOperation(unit, UnitOperationTypes.MOVE_TO, tParameters)
		end
		return true
	elseif UnitManager.CanStartOperation(unit, UnitOperationTypes.SWAP_UNITS, nil, tParameters) then
		if not try then
			UnitManager.RequestOperation(unit, UnitOperationTypes.SWAP_UNITS, tParameters)
		end
		return true
	end
	return false
end

local function limit1turn(unit, endPlot)
	local dist = Turn2Plots(unit, { endPlot })
	return dist <= 1
end

--- DfsManager: Depth-First Search Generic Manager
-- @param sPlot The starting node (Plot object or Unit object)
-- @param exp A function(plot) that returns a list of adjacent plots for a given plot: {plot, plot, ...}, if nil then use Map.GetAdjacentPlots(plot:GetX(), plot:GetY())
-- @param vis An optional function(sPlot, plot) to process each visited plot. It can return a result or nil or false.
-- @return results: An array of visited and unfiltered plots or an array of return values.
function DfsManager(s, vis, exp)
	local defaultExp = function(plot)
		return Map.GetAdjacentPlots(plot:GetX(), plot:GetY())
	end
	if not exp then
		exp = defaultExp
	end
	local visited = {}
	local plots = {}
	local results = {}
	local function visit(plot)
		local index = plot:GetIndex()
		if not visited[index] then
			visited[index] = true
			local result = plot
			if vis ~= nil then
				result = vis(s, plot)
			end
			if result ~= nil and result ~= false then
				table.insert(plots, plot)
				results[index] = result
				local adjs = exp(plot)
				for _, adj in pairs(adjs) do
					visit(adj)
				end
			end
		end
	end
	local sPlot = Map.GetPlot(s:GetX(), s:GetY())
	visit(sPlot)
	return plots, results
end

-- @parm grader a function(plot or unit) that returns a non-negative number or boolean, for the first case larger is better, for the second case for validation
function Shift(unit, grader)
	if grader(unit) == true then
		return false
	end
	for n = 1, 2 do
		local function limitNturn(u, t)
			local dist = Turn2Plots(u, { t })
			return dist <= n
		end
		local grader_wrap = function(p)
			local res = grader(p)
			if type(res) == "number" then
				return res
			end
			if res == true then
				return math.huge
			end
			return -math.huge
		end
		local plots = DfsManager(unit, limitNturn)
		local grades = graph(plots, grader_wrap)
		local bestGrade, bestPlot = max(grades)
		if bestGrade > -math.huge and bestPlot then
			Move2Plot(unit, bestPlot)
			return true
		end
	end
	return false
end

function Rush(unit, lowBound)
	if unit:GetDamage() > 10 then
		return false
	end
	if not lowBound then
		lowBound = 0
	end
	return Shift(unit, function(p)
		local dist = Distance2Front(p)
		if dist < lowBound then
			return false
		end
		return -dist
	end)
end

function Escape(unit)
	print("Escaping unit:", unit:GetID(), "at", unit:GetX(), unit:GetY())
	return Shift(unit, function(p)
		local dist = Distance2Front(p)
		if dist <= 4 then
			return dist
		end
		return false
	end)
end

function GetEnemies(player)
	local ans = {}
	local players = Game.GetPlayers()
	for _, enemy in pairs(players) do
		if enemy ~= nil and enemy:GetDiplomacy() ~= nil and enemy:GetDiplomacy():IsAtWarWith(player) then
			table.insert(ans, enemy)
		end
	end
	return ans
end

function GetVassals(player)
	local ans = {}
	local players = Game.GetPlayers()
	local playerID = player:GetID()
	for _, ally in pairs(players) do
		if ally ~= nil then
			local influ = ally:GetInfluence()
			if influ ~= nil then
				local suz = influ:GetSuzerain()
				if suz == playerID then
					table.insert(ans, ally)
				end
			end
		end
	end
	return ans
end

function GetPlayerUnits(player)
	if not player then
		return {}
	end
	local units = {}
	for _, unit in player:GetUnits():Members() do
		if unit and unit:GetCombat() > 0 then
			table.insert(units, unit)
		end
	end
	return units
end

function GetEnemyUnits(player)
	local enemies = GetEnemies(player)
	local units = {}
	for _, enemy in pairs(enemies) do
		for _, unit in enemy:GetUnits():Members() do
			if unit and unit:GetCombat() > 0 then
				table.insert(units, unit)
			end
		end
	end
	return units
end

function GetStrength(units)
	local typeName = units.TypeName or ""
	if string.find(typeName, "Unit") then
		units = { units }
	end
	local strength = 0
	for _, unit in pairs(units) do
		local combat = max({ unit:GetCombat(), unit:GetRangedCombat(), unit:GetBombardCombat() })
		strength = strength + math.pow(2, combat / 10)
	end
	strength = math.log(strength, 2) * 10
	return strength
end

function GetStrengthDiff(player)
	local pUnits = GetPlayerUnits(player)
	local eUnits = GetEnemyUnits(player)
	if #eUnits == 0 then
		return 1000
	end
	local pStrength = GetStrength(pUnits)
	local eStrength = GetStrength(eUnits)
	if eStrength == 0 then
		return 1000
	end
	return pStrength - eStrength
end

function GetPlotNearbyEnemy(x, y)
	local units = GetEnemyUnits(Game.GetLocalPlayer())
	local eUnits = {}
	for _, unit in pairs(units) do
		if Map.GetPlotDistance(x, y, unit:GetX(), unit:GetY()) <= 2 then
			table.insert(eUnits, unit)
		end
	end
	return eUnits
end

-- TODO: test if cities are included
function GetMeleeTargets(pUnit)
	local adjs = DfsManager(pUnit, limit1turn)
	local ans = {}
	for _, plot in pairs(adjs) do
		local uPlots = Units.GetUnitsInPlot(plot)
		for _, eUnit in pairs(uPlots) do
			if eUnit ~= nil then
				if table_contains(enemiesID, eUnit:GetOwner()) then
					table.insert(ans, eUnit)
				end
			end
		end
		if table_contains(eCityLocs, plot:GetIndex()) then
			table.insert(ans, CityManager.GetCityAt(plot:GetX(), plot:GetY()))
		end
	end
	return ans
end
--	local res  = CombatManager.SimulateAttackVersus(unit, eUnit)

function MeleeAttackPlot(pUnit, plot)
	local x = plot:GetX()
	local y = plot:GetY()
	local tParameters = {
		[UnitOperationTypes.PARAM_X] = x,
		[UnitOperationTypes.PARAM_Y] = y,
	}
	tParameters[UnitOperationTypes.PARAM_MODIFIERS] = UnitOperationMoveModifiers.ATTACK

	if UnitManager.CanStartOperation(pUnit, UnitOperationTypes.MOVE_TO, nil, tParameters) then
		UnitManager.RequestOperation(pUnit, UnitOperationTypes.MOVE_TO, tParameters)
	end
end

--- Return cities
--- TODO: test update
function GetCities(init)
	local res = {}
	local players = Game.GetPlayers()
	for _, player in pairs(players) do
		if player.GetCities then
			local cities = player:GetCities() or {}
			for _, city in cities:Members() do
				table.insert(res, city)
			end
		end
	end
	if not init then
		return res
	end
	aCities = res
	cityLocs = Index2Plots(aCities)
	eCities = filter(aCities, function(c)
		return table_contains(enemiesID, c:GetOwner())
	end)
	eCityLocs = Index2Plots(eCities)
end

function GetCityPlots(city)
	local cityPlotIndex = Map.GetCityPlots():GetPurchasedPlots(city)
	local ans = {}
	for _, index in pairs(cityPlotIndex) do
		table.insert(ans, Map.GetPlotByIndex(index))
	end
	return ans
end

function GetOwnedPlots(player)
	if not player or not player.GetCities or not player:GetCities() then
		return {}
	end
	local ans = {}
	for _, city in player:GetCities():Members() do
		local cityPlots = GetCityPlots(city)
		for _, plot in pairs(cityPlots) do
			table.insert(ans, plot)
		end
	end
	return ans
end

function Plots2Index(plot)
	return map(plot, function(p)
		return p:GetIndex()
	end)
end

function Index2Plots(index)
	return map(index, function(i)
		return Map.GetPlotByIndex(i)
	end)
end

function GetZOC(unit)
	return Map.GetAdjacentPlots(unit:GetX(), unit:GetY())
end

-- TODO: Reconsider the following 4 functions
--- always return back table of indexs
function GetPlayerZone(player)
	local domain = GetOwnedPlots(player)
	-- domain = filter(domain, function(p)
	-- 	return not p:IsMountain()
	-- end)
	domain = Plots2Index(domain)
	local pUnits = GetPlayerUnits(player)
	local pUnitLocs = Plots2Index(map(pUnits, function(u)
		return Map.GetPlot(u:GetX(), u:GetY())
	end))
	return union(domain, pUnitLocs)
end

function GetVassalZone(player)
	local vassals = GetVassals(player)
	local vZones = map_union(vassals, GetPlayerZone)
	return vZones
end

function GetEnemyZone(player)
	local enemies = GetEnemies(player)
	local eZones = map_union(enemies, GetPlayerZone)
	return eZones
end

--- Return plots rather than indexs
function GetFrontier(player)
	playerZone = GetPlayerZone(player)
	local vassalZone = GetVassalZone(player)
	playerZone = union(playerZone, vassalZone)
	enemyZone = GetEnemyZone(player)
	-- TODO: simplify this
	local pUnits = GetPlayerUnits(player)
	local pUnitLocs = Plots2Index(map(pUnits, function(u)
		return Map.GetPlot(u:GetX(), u:GetY())
	end))
	enemyZone = subtract(enemyZone, pUnitLocs)
	local frontier = {}
	for _, plot in pairs(Index2Plots(playerZone)) do
		if not table_contains(enemyZone, plot:GetIndex()) then
			local adjPlots = Map.GetAdjacentPlots(plot:GetX(), plot:GetY())
			local contain = false
			for _, adj in pairs(adjPlots) do
				local adjIndex = adj:GetIndex()
				if table_contains(enemyZone, adjIndex) then
					contain = true
					break
				end
			end
			if contain then
				table.insert(frontier, plot)
			end
		end
	end
	frontier = filter(frontier, function(p)
		return not p:IsMountain()
	end)
	return frontier
end

--- returns negative if the plot is in enemy zone
-- @parm plot can also be replace with other table can return GetX() and GetY()
function Distance2Front(plot)
	plot = Map.GetPlot(plot:GetX(), plot:GetY())
	local index = plot:GetIndex()
	local dist = Distance2Plots(plot, front)
	if enemyZone and table_contains(enemyZone, index) then
		return -dist
	end
	return dist
end

function GetLocalPlayer(playerID)
	if not Players[playerID] then
		return
	end
	local player = Players[playerID]
	if not player.IsHuman or player:IsHuman() == false then
		return
	end
	return player
end

function Test2(playerID)
	local player = GetLocalPlayer(playerID)
	if not player then
		return
	end
	debugTurnInfo(playerID)
end

function Test1(playerID)
	local player = GetLocalPlayer(playerID)
	if not player then
		return
	end
	debugTurnInfo(playerID)
	-- Do not remove above debug output
	for _, unit in player:GetUnits():Members() do
		if IsAir(unit) then
			UnitRangeAttack(unit)
		end
	end
end

function Test(playerID)
	if not Players[playerID]:IsHuman() then
		return
	end
end
Events.PlayerTurnActivated.Add(OnPlayerTurnActivated)
-- Events.PlayerTurnActivated.Add(Test1)

--- Applies for citie sand units including planes
function GetRangeAttackTargets(attacker, air)
	local typeName = attacker.TypeName or ""
	local plots = {}
	local prefix = "RANGE"
	if air then
		prefix = "AIR"
	end
	if string.find(typeName, "City") or string.find(typeName, "District") then
		local res = CityManager.GetCommandTargets(attacker, CityCommandTypes.RANGE_ATTACK, true) or {}
		plots = res[CityOperationResults.PLOTS] or {}
		plots = Index2Plots(plots)
	elseif string.find(typeName, "Unit") then
		local res = UnitManager.GetOperationTargets(attacker, UnitOperationTypes[prefix .. "_ATTACK"]) or {}
		plots = res[UnitOperationResults.PLOTS] or {}
		plots = Index2Plots(plots)
	end
	plots = plots or {}
	return plots
end
