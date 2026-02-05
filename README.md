# Weak Robot Restaurant

A 2D restaurant simulation game built with Godot 4.5, designed for Human-Robot Interaction (HRI) delegation research. The game features a "weak" robot server that may need human assistance to complete tasks, enabling the study of when and how humans choose to help autonomous agents.

## Research Purpose

This project is developed for studying **human-robot interaction** and **task delegation** in collaborative scenarios. The simulation collects detailed episode data for **causal inference research**, tracking:

- Robot navigation and task completion
- Human intervention patterns
- Task success/failure conditions
- Interaction timing and behaviors

## Features

- **Robot Server**: An AI-powered robot that serves customers using behavior trees
- **Human Server**: Player-controlled character that can assist the robot
- **Customer System**: Dynamic customer spawning with food orders
- **Episode Logging**: Comprehensive data collection for research analysis
- **Behavior Tree AI**: Modular AI system for robot decision-making

## Project Structure

```
weak-robot-restaurant/
├── data/                    # Game assets (tilesets, sprites)
├── scenes/                  # Godot scene files
│   ├── Restaurant.tscn      # Main game scene
│   ├── RobotServer.tscn     # Robot character
│   ├── HumanServer.tscn     # Player character
│   ├── Customer.tscn        # Customer NPCs
│   └── items/               # Pickable items
├── scripts/                 # GDScript source files
│   ├── bt/                  # Behavior Tree system
│   │   ├── bt_core.gd       # BT core classes
│   │   ├── bt_actions.gd    # BT action nodes
│   │   └── bt_runner.gd     # BT execution runner
│   ├── RobotServer.gd       # Robot AI logic
│   ├── HumanServer.gd       # Player controller
│   ├── Customer.gd          # Customer behavior
│   ├── CustomerSpawner.gd   # Customer generation
│   ├── EpisodeLogger.gd     # Research data collection
│   ├── GameManager.gd       # Game state management
│   ├── TimeManager.gd       # In-game time system
│   └── TaskBus.gd           # Task event bus
└── project.godot            # Godot project config
```

## Requirements

- [Godot Engine 4.5+](https://godotengine.org/download)
- OpenAI API Key (optional, for LLM-based robot planning)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Qam1ng/weak-robot-restaurant.git
   ```

2. Open Godot Engine and import the project

3. (Optional) Set up OpenAI API key for LLM features:
   - Configure in `scripts/RobotServer.gd`

4. Run the project (F5 or Play button)

## Controls

| Key | Action |
|-----|--------|
| W / Up | Move up |
| S / Down | Move down |
| A / Left | Move left |
| D / Right | Move right |
| E | Interact |

## Data Collection

Episode data is automatically saved to:
- **JSON files**: `user://data/episodes/ep_*.json` (detailed event logs)
- **CSV summary**: `user://data/episodes_summary.csv` (aggregated metrics)

### Collected Metrics

- Episode duration
- Task success/failure
- Player intervention events
- Robot navigation path
- Stuck/evasion counts
- Action sequences

## Architecture

### Behavior Tree System

The robot uses a custom behavior tree implementation:
- `bt_core.gd`: Base classes (Task, Composite, Decorator)
- `bt_actions.gd`: Action nodes (Move, PickUp, Serve, etc.)
- `bt_runner.gd`: Tree execution and state management

### Autoload Singletons

- **TaskBus**: Global event bus for task-related signals
- **EpisodeLogger**: Research data collection singleton
- **GameManager**: Game state and flow control

## License

This project is for academic research purposes.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Contact

For questions about the research or collaboration opportunities, please open an issue on GitHub.
