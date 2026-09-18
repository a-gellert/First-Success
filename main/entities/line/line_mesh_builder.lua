-- main/entities/line/line_mesh_builder.lua
local M = {}

-- Вычисление перпендикуляра к сегменту (левая нормаль)
local function get_segment_normal(p1, p2)
	local dir = p2 - p1
	local len = vmath.length(dir)
	if len < 0.0001 then
		return vmath.vector3(0, 1, 0)
	end
	dir = dir * (1 / len)
	return vmath.vector3(-dir.y, dir.x, 0)
end

function M.create_line_buffer(points, width, origin_pos)
	origin_pos = origin_pos or vmath.vector3(0, 0, 0)
	local count = #points
	if count < 2 then return nil end

	local segments = count - 1
	local num_vertices = segments * 6

	local buf = buffer.create(num_vertices, {
		{ name = hash("position"),  type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
		{ name = hash("texcoord0"), type = buffer.VALUE_TYPE_FLOAT32, count = 2 }
	})

	local sp = buffer.get_stream(buf, hash("position"))
	local su = buffer.get_stream(buf, hash("texcoord0"))

	local half_w = width * 0.5
	local pi, ui = 1, 1

	-- Функция записи вершины с жестко заданным Z
	local function push_vertex(px, py, u, v)
		sp[pi], sp[pi + 1], sp[pi + 2] = px, py, 0.5
		su[ui], su[ui + 1]            = u, v

		pi = pi + 3
		ui = ui + 2
	end

	for i = 1, segments do
		-- Локальные координаты относительно origin_pos
		local pA = points[i] - origin_pos
		local pB = points[i + 1] - origin_pos

		-- Нормаль сегмента
		local norm = get_segment_normal(pA, pB)
		local offsetX = norm.x * half_w
		local offsetY = norm.y * half_w

		-- 4 угла прямоугольника сегмента
		local aL_x, aL_y = pA.x + offsetX, pA.y + offsetY
		local aR_x, aR_y = pA.x - offsetX, pA.y - offsetY
		local bL_x, bL_y = pB.x + offsetX, pB.y + offsetY
		local bR_x, bR_y = pB.x - offsetX, pB.y - offsetY

		local uA = (i - 1) / segments
		local uB = i / segments

		-- Строгий порядок обхода против часовой стрелки (CCW):
		-- Треугольник 1: aL -> aR -> bL
		push_vertex(aL_x, aL_y, uA, 1.0)
		push_vertex(aR_x, aR_y, uA, 0.0)
		push_vertex(bL_x, bL_y, uB, 1.0)

		-- Треугольник 2: aR -> bR -> bL
		push_vertex(aR_x, aR_y, uA, 0.0)
		push_vertex(bR_x, bR_y, uB, 0.0)
		push_vertex(bL_x, bL_y, uB, 1.0)
	end

	return buf
end

return M