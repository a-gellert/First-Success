-- main/entities/ball/ball_config.lua
local M = {}

-- Постоянная скорость перемещения мяча (в пикселях / единицах в секунду)
M.speed = 250

--- Установить новую скорость мяча
-- @param speed number
function M.set_speed(speed)
	M.speed = speed
end

--- Получить текущую скорость мяча
-- @return number
function M.get_speed()
	return M.speed
end

return M
