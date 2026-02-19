# Weak Robot Restaurant 项目改进计划

## 问题1: 导航系统重构 - 基于网格的4方向移动

### 当前问题
- 使用 `NavigationAgent2D` 配合复杂的绕行逻辑 (`_evasion_active`, `_stuck_timer`)
- 代码冗长且容易出bug（例如 `CustomerSpawner.gd` 有大量重复代码块需要清理）
- 角色移动不够"游戏化"，像宝可梦那种经典RPG

### 解决方案：AStarGrid2D 网格寻路

#### 核心原理

**初始化阶段:**
1. TileMap场景 → 扫描LayerWalls的所有Tile
2. 检查Tile是否有碰撞 → 是则标记为障碍物(solid=true)，否则保持可通行
3. AStarGrid2D网格构建完成

**寻路阶段:**
1. 角色世界坐标 → 除以cell_size得到网格坐标（例如(160,80)÷16=(10,5)）
2. 目标世界坐标 → 同样转换（例如(320,160)÷16=(20,10)）
3. 调用 `astar.get_point_path((10,5),(20,10))`
4. 返回网格坐标数组 `[(10,5),(11,5),(12,5)...(20,10)]`

**移动阶段:**
1. 转换回世界坐标（每个点×16+8得到格子中心）
2. 角色依次移动到每个点
3. 当距离当前点小于4px时，对齐位置并取下一个点
4. 路径为空时到达目的地

#### 详细技术实现

**步骤1: 创建GridNavigator.gd - 从TileMap构建网格**

```gdscript
# scripts/GridNavigator.gd
class_name GridNavigator
extends Node

var astar: AStarGrid2D
var cell_size: Vector2i = Vector2i(16, 16)  # 与TileMap的tile大小一致

func _ready():
    astar = AStarGrid2D.new()
    
    # 设置网格覆盖区域 (根据Restaurant.tscn的范围)
    # 当前场景大约从(-374,-518)到(470,326)
    # 转换为格子: 约(-24,-33)到(30,21)
    astar.region = Rect2i(-24, -33, 54, 54)
    astar.cell_size = cell_size
    astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER  # 只允许上下左右4方向
    astar.update()
    
    # 从LayerWalls标记障碍物
    var tilemap = get_tree().current_scene.get_node("TileMap/LayerWalls")
    for cell in tilemap.get_used_cells():
        astar.set_point_solid(cell, true)  # 有墙的格子不可通行
    
    # 也可以从LayerFurniture标记桌椅为障碍
    var furniture = get_tree().current_scene.get_node("TileMap/LayerFurnitureCarpet/LayerFurnitureBot")
    for cell in furniture.get_used_cells():
        astar.set_point_solid(cell, true)

func get_path_to(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
    # 世界坐标 -> 网格坐标
    var from_cell = Vector2i(int(from_world.x / cell_size.x), int(from_world.y / cell_size.y))
    var to_cell = Vector2i(int(to_world.x / cell_size.x), int(to_world.y / cell_size.y))
    
    # 确保起点和终点不在障碍物内
    if astar.is_point_solid(from_cell):
        from_cell = _find_nearest_walkable(from_cell)
    if astar.is_point_solid(to_cell):
        to_cell = _find_nearest_walkable(to_cell)
    
    # A*计算路径
    var cell_path = astar.get_point_path(from_cell, to_cell)
    
    # 网格坐标 -> 世界坐标 (每个格子的中心点)
    var world_path: PackedVector2Array = []
    for cell in cell_path:
        var center = Vector2(cell.x * cell_size.x + cell_size.x / 2, 
                            cell.y * cell_size.y + cell_size.y / 2)
        world_path.append(center)
    
    return world_path

func _find_nearest_walkable(cell: Vector2i) -> Vector2i:
    # 在周围8格中找到最近的可行走格子
    for offset in [Vector2i(0,1), Vector2i(0,-1), Vector2i(1,0), Vector2i(-1,0)]:
        var neighbor = cell + offset
        if not astar.is_point_solid(neighbor):
            return neighbor
    return cell  # 找不到就返回原点
```

**步骤2: 修改角色移动逻辑**

```gdscript
# 在Customer.gd或RobotServer.gd中
var grid_nav: GridNavigator  # 引用
var path_queue: PackedVector2Array = []
var current_waypoint: Vector2 = Vector2.ZERO

func _ready():
    grid_nav = get_node("/root/Restaurant/GridNavigator")  # 或通过Autoload

func navigate_to(destination: Vector2):
    path_queue = grid_nav.get_path_to(global_position, destination)
    if path_queue.size() > 1:
        path_queue.remove_at(0)  # 移除起点(当前位置)
        current_waypoint = path_queue[0]
        path_queue.remove_at(0)

func _physics_process(delta):
    if current_waypoint == Vector2.ZERO:
        velocity = Vector2.ZERO
        return
    
    var to_waypoint = current_waypoint - global_position
    var distance = to_waypoint.length()
    
    if distance < 4.0:  # 到达当前路径点
        global_position = current_waypoint  # 精确对齐到格子中心
        
        if path_queue.is_empty():
            current_waypoint = Vector2.ZERO  # 完成导航
            _on_navigation_finished()
        else:
            current_waypoint = path_queue[0]
            path_queue.remove_at(0)
    else:
        # 逐格移动 - 只在4个方向中选择主方向
        var direction = Vector2.ZERO
        if abs(to_waypoint.x) > abs(to_waypoint.y):
            direction.x = sign(to_waypoint.x)
        else:
            direction.y = sign(to_waypoint.y)
        
        velocity = direction * move_speed
        move_and_slide()
        _update_animation(direction)
```

#### 与当前系统对比

| 特性 | 当前NavigationAgent2D | 新AStarGrid2D |
|------|----------------------|---------------|
| 移动方式 | 平滑曲线+实时避障 | 逐格4方向移动 |
| 代码复杂度 | 高(evasion/stuck检测500+行) | 低(路径队列~50行) |
| 视觉效果 | 现代游戏风格 | 经典宝可梦/Zelda风格 |
| 路径计算 | 每帧更新 | 一次计算完整路径 |
| 多角色处理 | NavigationAgent冲突 | 可动态标记占用格子 |

#### 文件修改清单
1. 新建 `scripts/GridNavigator.gd`
2. 修改 `scripts/Customer.gd` - 移除NavigationAgent2D相关代码
3. 修改 `scripts/RobotServer.gd` - 移除NavigationAgent2D和bt_actions中的复杂导航
4. 修改 `scripts/bt/bt_actions.gd` - 简化ActNavigate类
5. 清理 `scripts/CustomerSpawner.gd` - 移除268行后的重复代码

---

## 问题2: 增加场景复杂度

### 2.1 物品数量扩展
- 在 `Restaurant.tscn` 的 `InteractiveItems` 节点下添加更多食物
- 更新 `LocationMarkers` 中的食物位置标记
- 建议新增: `burger`, `soda`, `coffee`, `cake`

### 2.2 对话UI设计
当前 `DialogueManager.gd` 几乎为空，需要完整实现：
- **创建 `DialogueBubble.tscn`** - 气泡对话框场景
- **扩展 `HUD.gd`** - 任务提示、状态指示器

### 2.3 Delegation任务种类
扩展任务: `fetch_item`, `clean_table`, `refill_station`, `guide_customer`

### 2.4 突发事件系统
创建 `EventManager.gd` - 随机触发事件导致机器人需要delegation

### 2.5 场景数量
创建多个餐厅布局变体场景

---

## 问题3: 可视化可调节变量设置

创建 `SettingsPanel.tscn` - 按ESC/F10打开，包含时间流速、顾客间隔、机器人速度等参数滑块

---

## 问题4: 参与者调查问卷 (MBTI风格)

创建 `SurveyScreen.tscn` - 游戏启动前显示，10-16个问题，5点量表，数据保存到JSON

---

## 实施顺序

1. 清理CustomerSpawner.gd重复代码
2. 导航系统重构
3. 对话UI
4. 事件系统
5. 设置面板
6. 问卷系统

---
---

# Weak Robot Restaurant Improvement Plan

## Issue 1: Navigation System Refactor - Grid-Based 4-Direction Movement

### Current Problems
- Uses `NavigationAgent2D` with complex evasion logic (`_evasion_active`, `_stuck_timer`)
- Code is verbose and bug-prone (e.g., `CustomerSpawner.gd` has duplicate code blocks)
- Movement doesn't feel "game-like" compared to classic RPGs like Pokemon

### Solution: AStarGrid2D Grid-Based Pathfinding

#### Core Concept

**Initialization Phase:**
1. TileMap Scene → Scan all tiles in LayerWalls
2. Check if tile has collision → Mark as solid if yes, keep walkable if no
3. AStarGrid2D grid is ready

**Pathfinding Phase:**
1. Actor world position → Divide by cell_size to get grid coords (e.g., (160,80)÷16=(10,5))
2. Target world position → Same conversion (e.g., (320,160)÷16=(20,10))
3. Call `astar.get_point_path((10,5),(20,10))`
4. Returns cell array `[(10,5),(11,5),(12,5)...(20,10)]`

**Movement Phase:**
1. Convert back to world coords (each point ×16+8 = cell center)
2. Actor moves to each point sequentially
3. When distance < 4px, snap position and get next point
4. When path is empty, destination reached

#### Implementation Steps

1. **Create `GridNavigator.gd`**
   - Scan TileMap walls/furniture to build walkable grid
   - Use `AStarGrid2D` with `DIAGONAL_MODE_NEVER` for 4-direction only
   - Convert world coordinates to grid cells and back

2. **Modify Character Scripts**
   - Remove `NavigationAgent2D` dependencies
   - Use path queue from GridNavigator
   - Move step-by-step to each waypoint

3. **Cleanup `CustomerSpawner.gd`**
   - Remove duplicate code after line 268

#### Comparison Table

| Feature | Current NavigationAgent2D | New AStarGrid2D |
|---------|--------------------------|-----------------|
| Movement | Smooth curves + real-time avoidance | Step-by-step 4-direction |
| Code complexity | High (500+ lines for evasion) | Low (~50 lines path queue) |
| Visual style | Modern game | Classic Pokemon/Zelda |
| Path calculation | Per-frame updates | One-time full path |

---

## Issue 2: Increase Scene Complexity

- **2.1 More Items**: Add `burger`, `soda`, `coffee`, `cake`
- **2.2 Dialogue UI**: Create `DialogueBubble.tscn`, expand HUD
- **2.3 Task Types**: 1. Server's Own Tasks - `clean_table`, `refill_station`, 2. Delegaton Task - `fetch_food`, `remove_obstacle`, `charge_robot`
- **2.4 Event System**: `EventManager.gd` for random events requiring delegation
- **2.5 Scene Variants**: More scene items for example if we need task `remove_obstacle` we will need `obstacles`, if we need task `charge_robot` we will need `charge station` , random maps, random layouts(one single map for now).

---

## Issue 3: Visual Settings Panel

Create `SettingsPanel.tscn` - Press ESC/F10 to open, includes sliders for time speed, spawn interval, robot speed, etc.

---

## Issue 4: Participant Survey (MBTI-style)

Create `SurveyScreen.tscn` - Shown before game starts, 10-16 questions, 5-point Likert scale, saves to JSON. Not in Godot, but an extra web survey before enter game.

---

## Implementation Order

1. Navigation system refactor
2. Dialogue UI
3. Event system
4. Settings panel
5. Survey system

