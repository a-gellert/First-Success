-- main/entities/line/line_mesh_builder.lua
local M = {}

--- Сглаживание траектории алгоритмом Чайкина (Chaikin's Corner Cutting)
-- Превращает ломаные углы между сегментами в плавную скругленную кривую (B-сплайн)
-- @param points table массив точек vector3
-- @param iterations number количество итераций сглаживания
-- @return table сглаженный массив точек vector3
function M.smooth_points(points, iterations)
	iterations = iterations or 1
	if not points or #points < 3 or iterations <= 0 then
		return points
	end

	local current = points
	for _ = 1, iterations do
		local smoothed = {}
		local count = #current

		-- Первая точка сохраняется без изменений
		table.insert(smoothed, current[1])

		for i = 1, count - 1 do
			local pA = current[i]
			local pB = current[i + 1]

			-- Q = 0.75 * A + 0.25 * B
			local q = vmath.vector3(
				0.75 * pA.x + 0.25 * pB.x,
				0.75 * pA.y + 0.25 * pB.y,
				0.5 * (pA.z + pB.z)
			)

			-- R = 0.25 * A + 0.75 * B
			local r = vmath.vector3(
				0.25 * pA.x + 0.75 * pB.x,
				0.25 * pA.y + 0.75 * pB.y,
				0.5 * (pA.z + pB.z)
			)

			table.insert(smoothed, q)
			table.insert(smoothed, r)
		end

		-- Последняя точка сохраняется без изменений
		table.insert(smoothed, current[count])
		current = smoothed
	end

	return current
end

--- Фильтрация повторяющихся или чересчур близких точек
local function filter_close_points(points, min_dist)
	min_dist = min_dist or 0.5
	local min_dist_sq = min_dist * min_dist
	local filtered = {}

	for i = 1, #points do
		local p = points[i]
		if #filtered == 0 then
			table.insert(filtered, p)
		else
			local prev = filtered[#filtered]
			local dx = p.x - prev.x
			local dy = p.y - prev.y
			if (dx * dx + dy * dy) > min_dist_sq then
				table.insert(filtered, p)
			end
		end
	end

	return filtered
end

--- Вычисление единичной левой 2D-нормали к вектору направления
local function get_direction_normal(dir)
	local len = vmath.length(dir)
	if len < 0.0001 then
		return vmath.vector3(0, 1, 0)
	end
	local inv_len = 1 / len
	return vmath.vector3(-dir.y * inv_len, dir.x * inv_len, 0)
end

--- Построение непрерывного сглаженного вершинного буфера (Miter Joint Ribbon)
-- Соединяет смежные сегменты общими вершинами на стыках без щелей и изломов
-- @param raw_points table массив точек линии
-- @param width number толщина линии
-- @param origin_pos vector3 смещение начала координат
-- @param smooth_iterations number количество итераций сглаживания кривой (по умолчанию 1)
-- @return buffer|nil, table|nil возвращает буфер вертексов и сглаженный список точек
function M.create_line_buffer(raw_points, width, origin_pos, smooth_iterations)
	origin_pos = origin_pos or vmath.vector3(0, 0, 0)
	if not raw_points or #raw_points < 2 then
		return nil, raw_points
	end

	-- 1. Сглаживание траектории (алгоритм Чайкина)
	smooth_iterations = (smooth_iterations ~= nil) and smooth_iterations or 1
	local points = M.smooth_points(raw_points, smooth_iterations)
	points = filter_close_points(points, 0.5)

	local count = #points
	if count < 2 then
		return nil, raw_points
	end

	local half_w = width * 0.5
	local segments = count - 1

	-- 2. Вычисление нормалей для каждого сегмента
	local seg_normals = {}
	for i = 1, segments do
		local pA = points[i]
		local pB = points[i + 1]
		seg_normals[i] = get_direction_normal(pB - pA)
	end

	-- 3. Вычисление сглаженных нормалей в стыках (Miter Normals) с ограничением удлинения
	local left_verts = {}
	local right_verts = {}
	local MITER_LIMIT = 2.0 -- Защита от острых шипов на крутых углах

	for i = 1, count do
		local P = points[i] - origin_pos
		local joint_norm
		local miter_factor = 1.0

		if i == 1 then
			joint_norm = seg_normals[1]
		elseif i == count then
			joint_norm = seg_normals[segments]
		else
			local n_prev = seg_normals[i - 1]
			local n_curr = seg_normals[i]
			local sum = n_prev + n_curr
			local sum_len = vmath.length(sum)

			if sum_len < 0.0001 then
				joint_norm = n_prev
				miter_factor = 1.0
			else
				joint_norm = sum * (1 / sum_len)
				local dot = joint_norm.x * n_curr.x + joint_norm.y * n_curr.y
				if dot > 0.1 then
					miter_factor = math.min(1.0 / dot, MITER_LIMIT)
				else
					miter_factor = MITER_LIMIT
				end
			end
		end

		local offset = joint_norm * (half_w * miter_factor)
		left_verts[i] = vmath.vector3(P.x + offset.x, P.y + offset.y, 0.5)
		right_verts[i] = vmath.vector3(P.x - offset.x, P.y - offset.y, 0.5)
	end

	-- 4. Создание непрерывного вершинного буфера (смежные сегменты делят общие вершины)
	local num_vertices = segments * 6
	local buf = buffer.create(num_vertices, {
		{ name = hash("position"),  type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
		{ name = hash("texcoord0"), type = buffer.VALUE_TYPE_FLOAT32, count = 2 }
	})

	local sp = buffer.get_stream(buf, hash("position"))
	local su = buffer.get_stream(buf, hash("texcoord0"))

	local pi, ui = 1, 1
	local function push_vertex(pos, u, v)
		sp[pi], sp[pi + 1], sp[pi + 2] = pos.x, pos.y, pos.z
		su[ui], su[ui + 1]            = u, v
		pi = pi + 3
		ui = ui + 2
	end

	for i = 1, segments do
		local uA = (i - 1) / segments
		local uB = i / segments

		local aL = left_verts[i]
		local aR = right_verts[i]
		local bL = left_verts[i + 1]
		local bR = right_verts[i + 1]

		-- Строгий порядок обхода против часовой стрелки (CCW):
		-- Треугольник 1: aL -> aR -> bL
		push_vertex(aL, uA, 1.0)
		push_vertex(aR, uA, 0.0)
		push_vertex(bL, uB, 1.0)

		-- Треугольник 2: aR -> bR -> bL
		push_vertex(aR, uA, 0.0)
		push_vertex(bR, uB, 0.0)
		push_vertex(bL, uB, 1.0)
	end

	return buf, points
end

return M