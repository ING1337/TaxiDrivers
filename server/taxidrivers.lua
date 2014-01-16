-- TaxiDrivers by ING

-- ##############################################################################################################

-- vehicle ID's that can be used as a taxi, leave empty to enable all vehicles
vehicles          = {8, 9, 12, 22, 23, 41, 66, 70}

-- main settings, the money system works with integers! avoid to produce payout values < 0.5
price             = 10   -- price per kilometer
payBonus          = true -- pay out a bonus when the passenger leave the taxi

update            = 2    -- defines the time in seconds between the script checks if a driver earned money
distancePayOut    = 500  -- the distance in meters for every payout the taxes
maxVelocity       = 250  -- the max velocity in km/h, if the driver was faster, no money paid out. it use the average speed for the last <distancePayOut> meters

-- defines how much the passenger have to pay of the taxes, all values are multiplier!
-- is the value 0.5, the passenger have to pay the half of the taxes, is it 1 the whole tax and so on...
passengerTax      = 0
passengerBonusTax = 0

-- values to calculate the bonus
-- formula: (drivenKM * bonusDistWeight) * (averageKMH * bonusTimeWeight) * bonusMultiplier
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
end

-- ##############################################################################################################

class 'Driver'

function Driver:__init(player)
	self.player      = player
	self.vehicle     = player:GetVehicle()
	self.passengers  = {}
end

function Driver:AddPassenger(player)
	table.insert(self.passengers, Passenger(player))
	Chat:Send(self.player, chatPrefix .. player:GetName() .. " is your passenger now", chatTextColor1)
	Chat:Send(player, chatPrefix .. "You are passenger of Taxidriver " .. self.player:GetName() .. " now, this cab costs you " .. math.floor(price * passengerTax) .. "$ per KM", chatTextColor1) 
end

function Driver:RemovePassenger(player)
	for i=1, #self.passengers, 1 do
		p = self.passengers[i]
		if player == p.player then
			local pos   = player:GetPosition()
			local dist  = Vector2.Distance(Vector2(pos.x, pos.z), p.startPosition)
			
			local money = dist > p.distance and (price / 1000) * (dist - p.distance) or 0
			local bonus = payBonus and ((dist * bonusDistWeight) * (dist / (globalTimer:GetMilliseconds() - p.startTime) * 3.6 * bonusTimeWeight)) * bonusMultiplier or 0
			
			self.player:SetMoney(self.player:GetMoney() + money + bonus)
			
			money = (money * passengerTax) + (bonus * passengerBonusTax)
			if money > 0 then p.player:SetMoney(p.player:GetMoney() - money) end

			Chat:Send(self.player, chatPrefix .. "Passenger " .. p.player:GetName() .. " leaves | bonus: " .. math.floor(bonus) .. "$ | distance: " .. math.floor(dist) .. " meters", chatTextColor1)
			table.remove(self.passengers, i)
			return
		end
	end
end

function Driver:Update(forceUpdate)
	local p, t, pos, dist
	local money = 0
	for i=1, #self.passengers, 1 do
		p    = self.passengers[i]
		pos  = p.player:GetPosition()
		pos  = Vector2(pos.x, pos.z)
		dist = Vector2.Distance(pos, p.startPosition) - p.distance --Sqr
		
		if forceUpdate or dist > distancePayOut then
			t = globalTimer:GetMilliseconds()
			if (dist / (t - p.time) * 3600) > maxVelocity then
				Chat:Send(self.player, chatPrefix .. "You are too fast!", chatTextColor2)
			else
				money = money + (price / 1000) * dist
				if passengerTax then
					if p.player:GetMoney() < money * passengerTax then
						Chat:Send(self.player, chatPrefix .. "Passenger " .. p.player:GetName() .. " has no money anymore!", chatTextColor2)
						p.player:SetPosition(p.player:GetPosition() + Vector3(0, 5, 0))
						self:RemovePassenger(p.player)
					else
						p.player:SetMoney(p.player:GetMoney() - money)
					end
				end
			end
			
			p.distance = p.distance + dist
			p.time     = t
		end
	end
	if money > 0 then
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
	Events:Subscribe("PlayerExitVehicle", self, self.PlayerExit)
	Events:Subscribe("PlayerQuit", self, self.PlayerExit)
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

function TaxiDrivers:Update(args)
	if self.timer:GetSeconds() < update then return end

	for i=1, #self.drivers, 1 do
		self.drivers[i]:Update(false)
	end

	self.timer:Restart()
end

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

function TaxiDrivers:PlayerExit(args)
	local d
	for i=1, #self.drivers, 1 do
		d = self.drivers[i]
		if d.player == args.player then 
			table.remove(self.drivers, i)
			break
		end
		d:RemovePassenger(args.player)
	end
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
