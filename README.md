<p align="center">
  <img src="https://github.com/try-containers/Containers/blob/main/.github/256.png?raw=true" height="128">
  <h1 align="center">Containers</h1>
</p>

A modern, native macOS application for managing Linux containers using Apple's container runtime. 

<p align="center">
  <a href="">
      <img src="https://github.com/try-containers/Containers/blob/main/.github/store_badge.svg">
  </a>
</p>

## Getting Started

### First Launch

1. Launch the Containers app from your Applications folder
2. The app will automatically initialize the container system on first launch
3. Once initialized, the dashboard will show the main interface with tabs for Containers and Images

### Managing Images

1. Click the **Images** tab to view and manage container images
2. To pull a new image:
   - Click the **Pull Image** button
   - Enter the image reference (e.g., `docker.io/library/nginx:latest`, `alpine:latest`, `ubuntu:latest`)
   - Click **Pull** to download the image
3. View image details by clicking on an image name
4. Delete unused images with the trash icon

### Creating and Running Containers

1. Click the **Containers** tab
2. Click **Create Container** to configure a new container:
   - Select an image from the dropdown (pull an image first if needed)
   - Configure resources (CPU cores, memory)
   - Add environment variables if needed
   - Set up port mappings to expose container services
   - Configure the command and arguments (optional - uses image defaults if not specified)
3. Click **Create** to create the container
4. Start the container using the play button
5. View container logs, details, and inspect configuration by clicking the container name

### Menu Bar

The Containers app also runs in your menu bar, showing the current system status. Click the menu bar icon to:
- Quickly start/stop the container system
- Open the dashboard
- Access settings

### System Requirements

- macOS 26.0 or later
- Apple Silicon Mac (M1/M2/M3/M4)

## Contributing

This is a community-led effort, so we welcome as many contributors who can help. Read the [Contribution Guide](https://github.com/try-containers/Containers/blob/main/CONTRIBUTING.md) for more information.

<a href="https://www.buymeacoffee.com/armartinez" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>
