# Containers

A modern, native macOS application for managing Linux containers using Apple's container runtime. Built with SwiftUI for a seamless Mac experience.

## Overview

Containers provides a graphical interface for Apple's container runtime, enabling you to create and manage lightweight Linux virtual machines on macOS. With its native design and intuitive interface, managing containers feels natural on your Mac.

## Features

### Container Management
- **Create & Configure**: Set up containers with custom names, ports, environment variables, and volume mounts
- **Lifecycle Control**: Start, stop, and delete containers with a single click
- **Real-time Monitoring**: View container status, logs, and running processes
- **Detailed Inspection**: Access comprehensive information about running containers including environment, ports, and volumes

### Image Management
- **Pull from Registry**: Download images from remote container registries
- **Build from Dockerfile**: Create custom images from Dockerfiles with configurable build arguments
- **Import/Export**: Load images from OCI-compatible tar archives or save existing images
- **Image Inspection**: View image details including architecture, OS, size, and associated containers

### Volume Management
- **Create Volumes**: Set up persistent storage with custom size and metadata
- **Mount to Containers**: Attach volumes to containers for data persistence
- **Volume Inspection**: Monitor volume usage and see which containers are using each volume
- **Flexible Configuration**: Configure driver options and labels for advanced use cases

### System Configuration
- **Timeout Settings**: Configure timeouts for system startup, shutdown, and container operations
- **DNS Configuration**: Set up DNS domains for container-to-host communication
- **Menu Bar Integration**: Quick access to system status and controls from the menu bar

## Prerequisites

None! This application is self-contained and includes everything needed to run containers on macOS.

## Installation

### Download Pre-built App
Download the latest signed DMG from the [Releases page](https://github.com/yourusername/containers/releases)

### Build from Source
1. Clone the repository
2. Open `Containers.xcodeproj` in Xcode 16 or later
3. Build and run the Development scheme

## Getting Started

1. Launch the Containers app
2. The app will automatically initialize the container system
3. Start managing containers, images, and volumes right away

## System Requirements

- macOS 14.0 (Sonoma) or later
- Admin privileges (required for certain operations like DNS configuration)

## Architecture

### Core Components

- **ContainerSystem**: Core framework managing the container runtime interface
- **Managers**: Specialized managers for containers, images, volumes, and DNS
- **ViewModels**: SwiftUI view models providing reactive data binding
- **Native UI**: Modern macOS interface built entirely with SwiftUI

### Key Technologies

- SwiftUI for native macOS UI
- Swift Concurrency (async/await) for asynchronous operations
- Combine framework for reactive state management
- OCI (Open Container Initiative) standards compliance

## Project Structure

```
Containers/
├── Containers/              # Main application
│   ├── Views/              # SwiftUI views
│   ├── ViewModels/         # View models
│   ├── Models/             # Data models
│   └── Extensions/         # Swift extensions
├── ContainerSystem/        # Core container runtime interface
│   ├── Managers/           # Container, Image, Volume managers
│   ├── Services/           # System services
│   └── Models/             # Domain models
└── ContainerSystemTests/   # Unit tests
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

### Development Setup

1. Clone the repository
2. Open `Containers.xcodeproj` in Xcode
3. Select the Development scheme
4. Build and run

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI best practices
- Maintain 4-space indentation
- Add descriptive comments for complex logic

## Known Limitations

- Requires macOS 14.0 or later
- Some advanced container features may not be exposed in the UI

## Roadmap

### Planned Features
- Network management
- Docker Compose support
- Container terminal access
- Advanced image configuration
- Container resource monitoring
- Import/export container configurations

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Built on top of [Apple's container runtime](https://github.com/apple/container)
- Original concept by Itsuki
- Modernization and enhancements by Axel Martinez

## Support

For issues, feature requests, or questions:
- Open an issue on GitHub
- Check existing documentation
- Review the container runtime documentation

---

**Note**: This application is a third-party GUI and is not affiliated with or endorsed by Apple Inc.
