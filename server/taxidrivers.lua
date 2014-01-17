-- TaxiDrivers by ING

-- ##############################################################################################################

-- vehicle ID's that can be used as a taxi, leave empty to enable all vehicles
vehicles          = {8, 9, 12, 22, 23, 41, 66, 70}

-- main settings, the jcmp money system works with integers! avoid to produce payout values < 0.5
price             = 10   -- price per kilometer
penalty           = 100  -- money the driver has to pay to the passenger when he dies in the taxi
payBonus          = true -- pay out a bonus when the passenger leave the taxi

update            = 2    -- defines the time in seconds between the script checks if a driver earned money
distancePayOut    = 500  -- the distance in meters for every payout the taxes
maxVelocity       = 50  -- the max velocity in km/h, if the driver was faster, no money paid out. it use the average speed for the last <distancePayOut> meters

-- defines how much the passenger have to pay of the taxes, all values are multiplier!
-- is the value 0.5, the passenger have to pay the half of the taxes, is it 1 the whole tax and so on...
passengerTax      = 0
passengerBonusTax = 0

-- values to calculate the bonus
-- formula: (drivenKM * bonusDistWeight) * ((averageKMH / 1000) * bonusTimeWeight) * bonusMultiplier
bonusMultiplier   = 0.5
bonusDistWeight   = 1
bonusTimeWeight   = 0.5

chatTextColor1    = Color(255, 255, 155) -- color for normal messages
chatTextColor2    = Color(255, 55, 55)   -- color for warnings
chatPrefix        = "[Taxi] "            -- text that shows in fornt of every message

-- ##############################################################################################################

class 'Passenger'

function Passenger:__init(player)
	self.player        = player
	local pos          = player:GetPosition()
	
	self.startPosition = Vector2(pos.x, pos.z)
	self.startTime     = globalTimer:GetMilliseconds()
	
	self.time          = self.startTime
	self.distance      = 0
	self.payed         = 0
end

-- ##############################################################################################################

class 'Driver'

function Driver:__init(player)
	self.player      = player
	self.vehicle     = player:GetVehicle()
	self.passengers  = {}
	self.earned      = 0
end

function Driver:AddPassenger(player)
	table.insert(self.passengers, Passenger(player))
	Chat:Send(self.player, chatPrefix .. player:GetName() .. " is your passenger now", chatTextColor1)
	Chat:Send(player, chatPrefix .. "You are passenger of Taxidriver " .. self.player:GetName() .. " now, this cab costs you " .. math.floor(price * passengerTax) .. "$ per km", chatTextColor1) 
end

function Driver:RemovePassenger(index, death)
		local p      = self.passengers[index]
		local player = p.player
		table.remove(self.passengers, index)
		
		local pos    = player:GetPosition()
		local dist   = Vector2.Distance(Vector2(pos.x, pos.z), p.startPosition)
		local speed  = dist / (globalTimer:GetMilliseconds() - p.startTime) * 3600
		
		if speed > maxVelocity then
			Chat:Send(self.player, chatPrefix .. "Passenger " .. player:GetName() .. " leaves | To fast, no bonus! | distance: " .. math.floor(dist) .. "m | ~speed: " .. math.floor(speed) .. " km/h", chatTextColor2)
			return
		end
		
		if death then
			self.earned  = self.earned - (p.payed + penalty)
			self.player:SetMoney(self.player:GetMoney() - (p.payed + penalty))
			p.player:SetMoney(p.player:GetMoney() + (p.payed + penalty))
			Chat:Send(self.player, chatPrefix .. "Passenger " .. player:GetName() .. " died | payback: " .. p.payed .. "$ | penalty: " .. penalty .. "$", chatTextColor2)
			Chat:Send(player, chatPrefix .. "Taxidriver " .. self.player:GetName() .. " pays back your taxes (" .. p.payed .. "$) and a penalty (" .. penalty .. "$)", chatTextColor2)
		else
			local money  = dist > p.distance and (price / 1000) * (dist - p.distance) or 0
			local bonus  = payBonus and ((dist * bonusDistWeight) * ((speed / 1000) * bonusTimeWeight)) * bonusMultiplier or 0
			
			self.earned  = self.earned + money + bonus
			self.player:SetMoney(self.player:GetMoney() + money + bonus)
			
			money = (money * passengerTax) + (bonus * passengerBonusTax)
			if money > 0 then player:SetMoney(player:GetMoney() - money) end

			Chat:Send(self.player, chatPrefix .. "Passenger " .. player:GetName() .. " leaves | bonus: " .. math.floor(bonus) .. "$ | distance: " .. math.floor(dist) .. "m | ~speed: " .. math.floor(speed) .. " km/h", chatTextColor1)
		end
end

function Driver:EjectAllPassengers()
		for i=1, #self.passengers, 1 do
			self.passengers[i].player:SetPosition(self.passengers[i].player:GetPosition() + Vector3(0, 5, 0))
		end
end

function Driver:Update(forceUpdate)
	local p, v, pos, dist
	local t = globalTimer:GetMilliseconds()
	local money = 0
	
	for i=1, #self.passengers, 1 do
		p    = self.passengers[i]
		pos  = p.player:GetPosition()
		pos  = Vector2(pos.x, pos.z)
		dist = Vector2.Distance(pos, p.startPosition) - p.distance
		
		if forceUpdate or dist > distancePayOut then
			if (dist / (t - p.time) * 3600) > maxVelocity then
				Chat:Send(self.player, chatPrefix .. "You are too fast! Speed limit is at " .. maxVelocity .. " km/h", chatTextColor2)
			else
				money = money + (price / 1000) * dist
				if passengerTax > 0 then
					v = (price / 1000) * dist * passengerTax
					if p.player:GetMoney() < v then
						Chat:Send(self.player, chatPrefix .. "Passenger " .. p.player:GetName() .. " has no money anymore!", chatTextColor2)
						Chat:Send(p.player, chatPrefix .. "You have no more money!", chatTextColor2)
						p.player:SetPosition(p.player:GetPosition() + Vector3(0, 5, 0))
						self:RemovePassenger(i, false)
					else
						p.payed = p.payed + v
						p.player:SetMoney(p.player:GetMoney() - v)
					end
				end
			end
			
			p.distance = p.distance + dist
			p.time     = t
		end
	end
	if money > 0 then
		self.earned  = self.earned + money
		self.player:SetMoney(self.player:GetMoney() + money)
		Chat:Send(self.player, chatPrefix .. "Taxes payout " .. math.floor(money) .. "$", chatTextColor1)
	end
end

-- ##############################################################################################################

class 'TaxiDrivers'

function TaxiDrivers:__init()
	self.drivers  = {}
	self.timer    = Timer()

	Events:Subscribe("PlayerEnterVehicle", self, self.EnterVehicle)
	Events:Subscribe("PlayerExitVehicle", self, self.ExitVehicle)
	Events:Subscribe("PlayerQuit", self, self.ExitVehicle)
	Events:Subscribe("PlayerDeath", self, self.PlayerDeath)
	Events:Subscribe("PreTick", self, self.Update)
end

function TaxiDrivers:AddDriver(args)
	local driver = Driver(args.player)
	table.insert(self.drivers, driver)
	Chat:Send(args.player, chatPrefix .. "You are Taxidriver " .. tostring(#self.drivers) .. " now", chatTextColor1) 
	
	local occupants = args.vehicle:GetOccupants()
	if #occupants > 1 then
		for i=1, #occupants, 1 do
			if occupants[i] ~= args.player then driver:AddPassenger(occupants[i]) end
		end
	end
end

function TaxiDrivers:RemoveDriver(index)
	Chat:Send(self.drivers[index].player, chatPrefix .. "You leave your taxi, you earned " .. self.drivers[index].earned .. "$ with your last ride", chatTextColor1) 
	table.remove(self.drivers, index)
end

function TaxiDrivers:Update(args)
	if self.timer:GetSeconds() < update then return end

	for i=1, #self.drivers, 1 do
		self.drivers[i]:Update(false)
	end

	self.timer:Restart()
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function TaxiDrivers:EnterVehicle(args)
	if #vehicles > 0 and self:CheckVehicle(args.vehicle:GetModelId()) == false then return end

	if args.is_driver then
		self:AddDriver(args)
	else
		local p = args.vehicle:GetDriver()
		if p == nil then return end

		for i=1, #self.drivers, 1 do
			if p == self.drivers[i].player then 
				self.drivers[i]:AddPassenger(args.player)
				break
			end
		end
	end
end

function TaxiDrivers:ExitVehicle(args)
	local search = self:FindPlayer(args.player)
	if search then
		if search.passenger then
			search.driver:RemovePassenger(search.index, false)
		else
			self:RemoveDriver(search.index)
		end
	end
end

function TaxiDrivers:PlayerDeath(args)
	local search = self:FindPlayer(args.player)
	if search then
		if search.passenger then
			search.driver:RemovePassenger(search.index, true)
		else
			search.driver:EjectAllPassengers()
			search.driver.vehicle:SetHealth(0.1)
			self:RemoveDriver(search.index)
		end
	end
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function TaxiDrivers:FindPlayer(player)
	local d, p
	for i=1, #self.drivers, 1 do
		d = self.drivers[i]
		if d.player == player then return {driver = d, passenger = nil, index = i} end
		for j=1, #d.passengers, 1 do
			p = d.passengers[j]
			if p.player == player then return {driver = d, passenger = p, index = j} end
		end
	end
	return nil
end

function TaxiDrivers:CheckVehicle(id)
	for i=1, #vehicles, 1 do
		if id == vehicles[i] then return true end
	end
	return false
end

-- ##############################################################################################################

taxidrivers = TaxiDrivers()
globalTimer = Timer()
