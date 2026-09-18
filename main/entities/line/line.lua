-- main/entities/line/line.lua
-- Порт компонента Line из Unity:
-- public class Line : MonoBehaviour
-- {
--     [SerializeField] private LineRenderer _renderer;
--     [SerializeField] private EdgeCollider2D _collider;
--     [SerializeField] private float scaleCollider = 0.2f;
--     private readonly List<Vector2> _points = new List<Vector2>();
--     ...
-- }

local mesh_builder = require("main.entities.line.line_mesh_builder")

local Line = {}
Line.__index = Line

-- Реестр активных линий для проверки коллизий (аналог физической регистрации EdgeCollider2D)
Line.active_lines = {}

local line_counter = 0

--- Создание нового экземпляра Line
-- @param game_object_id hash/id созданного объекта из префаба (#line_mesh_factory)
-- @param origin_pos vector3 позиция спавна
-- @param line_width number толщина отображения линии
-- @param scale_collider number радиус коллизии (scaleCollider)
-- @param resolution number минимальная дистанция между точками (RESOLUTION)
-- @param smooth_iterations number количество итераций сглаживания кривой
function Line.new(game_object_id, origin_pos, line_width, scale_collider, resolution, smooth_iterations)
	local instance = setmetatable({}, Line)

	line_counter = line_counter + 1

	instance.id = game_object_id
	instance.origin_pos = origin_pos or vmath.vector3(0, 0, 0)
	instance.line_width = line_width or 12
	instance.scale_collider = scale_collider or (instance.line_width * 0.5)
	instance.resolution = resolution or 10
	instance.smooth_iterations = (smooth_iterations ~= nil) and smooth_iterations or 1

	-- private readonly List<Vector2> _points = new List<Vector2>();
	instance.points = {}

	-- _collider.points
	instance.collider_points = {}

	-- Ссылка на меш-компонент (аналог _renderer LineRenderer в Unity)
	instance.mesh_url = msg.url(nil, instance.id, "mesh")
	instance.buffer_path = "/line_mesh_" .. tostring(line_counter) .. ".bufferc"
	instance.buffer_res = nil

	-- Добавляем линию в список активных для симуляции физики
	table.insert(Line.active_lines, instance)

	return instance
end

--- Проверка дистанции между последней точкой и новой позицией
-- private bool CanAppend(Vector2 pos)
-- {
--     if (_renderer.positionCount == 0) return true;
--     return Vector2.Distance(_renderer.GetPosition(_renderer.positionCount - 1), pos) > DrawManager.RESOLUTION;
-- }
function Line:can_append(pos)
	if #self.points == 0 then
		return true
	end

	local last_point = self.points[#self.points]
	local diff = pos - last_point
	diff.z = 0
	local distance = vmath.length(diff)

	return distance > self.resolution
end

--- Добавление точки в линию и обновление визуала + коллайдера
-- public void SetPosition(Vector2 pos)
-- {
--     if (!CanAppend(pos)) return;
--     _points.Add(pos);
--     _renderer.positionCount++;
--     _renderer.SetPosition(_renderer.positionCount - 1, pos);
--     _collider.points = _points.ToArray();
--     _collider.edgeRadius = scaleCollider;
-- }
function Line:set_position(pos)
	if not self:can_append(pos) then
		return false
	end

	-- _points.Add(pos);
	table.insert(self.points, pos)

	-- Обновление отображения (_renderer: LineRenderer) в реальном времени со сглаживанием
	if #self.points >= 2 then
		local buf, smoothed_pts = mesh_builder.create_line_buffer(self.points, self.line_width, self.origin_pos, self.smooth_iterations)
		if buf then
			if not self.buffer_res then
				-- Создаем уникальный буфер-ресурс для конкретной линии
				self.buffer_res = resource.create_buffer(self.buffer_path, { buffer = buf })
				go.set(self.mesh_url, "vertices", self.buffer_res)
			else
				-- Обновляем существующий буфер новыми вершинами
				resource.set_buffer(self.buffer_res, buf)
			end
		end

		-- Обновление коллайдера: используем сглаженные точки для гладкого отскока
		self.collider_points = smoothed_pts or self.points
	else
		self.collider_points = self.points
	end

	return true
end

--- Удаление линии и очистка ресурсов
function Line:destroy()
	for i, line in ipairs(Line.active_lines) do
		if line == self then
			table.remove(Line.active_lines, i)
			break
		end
	end

	if self.id then
		pcall(go.delete, self.id)
		self.id = nil
	end
end

return Line
