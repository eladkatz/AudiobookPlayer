# Contributing to AudioBook Player

Thank you for your interest in contributing to AudioBook Player! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Workflow](#development-workflow)
4. [Coding Standards](#coding-standards)
5. [Commit Guidelines](#commit-guidelines)
6. [Pull Request Process](#pull-request-process)
7. [Testing](#testing)
8. [Documentation](#documentation)

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Respect different viewpoints and experiences

## Getting Started

### 1. Fork and Clone

```bash
# Fork the repository on GitHub
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/AudiobookPlayer.git
cd AudiobookPlayer
```

### 2. Set Up Development Environment

1. Open `AudioBookPlayer.xcodeproj` in Xcode
2. Configure signing (see [QUICK_START.md](QUICK_START.md))
3. Build the project (⌘ + B) to ensure everything compiles
4. Run the app (⌘ + R) to verify it works

### 3. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

**Branch Naming Convention**:
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `test/` - Test additions/updates

## Development Workflow

### 1. Make Your Changes

- Write clean, readable code
- Follow the existing code style
- Add comments for complex logic
- Update documentation as needed

### 2. Test Your Changes

- Test on iOS Simulator
- Test on physical device if possible
- Test edge cases and error scenarios
- Ensure no regressions

### 3. Commit Your Changes

```bash
git add .
git commit -m "Your descriptive commit message"
```

See [Commit Guidelines](#commit-guidelines) for message format.

### 4. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

## Coding Standards

### Swift Style Guide

Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/):

- Use descriptive names
- Prefer clarity over brevity
- Use camelCase for variables and functions
- Use PascalCase for types
- Use `MARK:` comments to organize code sections

### Code Organization

```swift
// MARK: - Properties
@Published var property: Type

// MARK: - Initialization
init() { }

// MARK: - Public Methods
func publicMethod() { }

// MARK: - Private Methods
private func privateMethod() { }
```

### Naming Conventions

- **Classes**: `PascalCase` (e.g., `AudioManager`)
- **Structs**: `PascalCase` (e.g., `Book`)
- **Functions**: `camelCase` (e.g., `loadBook(_:)`)
- **Variables**: `camelCase` (e.g., `currentTime`)
- **Constants**: `camelCase` (e.g., `clientID`)
- **Enums**: `PascalCase` with `camelCase` cases

### SwiftUI Best Practices

- Keep views focused and single-purpose
- Extract complex views into separate components
- Use `@State` for local view state
- Use `@ObservedObject` for shared state
- Use `@EnvironmentObject` for app-wide state

### Error Handling

- Use `do-catch` for operations that can fail
- Provide meaningful error messages
- Log errors for debugging
- Display user-friendly error messages in UI

Example:
```swift
do {
    try someOperation()
} catch {
    print("Error: \(error.localizedDescription)")
    // Display error to user
}
```

### Comments

- Add comments for complex logic
- Explain "why" not "what"
- Use `// MARK:` to organize code
- Document public APIs

Example:
```swift
// MARK: - File Operations

/// Downloads a book from Google Drive and imports it into the app
/// - Parameters:
///   - m4bFileID: The Google Drive file ID of the M4B file
///   - folderID: The Google Drive folder ID containing the file
/// - Returns: A Book object if successful, nil otherwise
func importBookFromGoogleDriveM4B(m4bFileID: String, folderID: String) async -> Book? {
    // Implementation
}
```

## Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Test additions/updates
- `chore`: Maintenance tasks

### Examples

```
feat(player): Add sleep timer functionality

Implement sleep timer that pauses playback after specified duration.
User can set timer in Settings view.

Closes #123
```

```
fix(google-drive): Fix authentication persistence issue

Authentication state was not being restored on app launch.
Added checkAuthenticationStatus() call in app initialization.

Fixes #456
```

```
docs(readme): Update setup instructions

Add iPad deployment instructions and troubleshooting section.
```

## Pull Request Process

### Before Submitting

1. **Update Documentation**: Update README, ARCHITECTURE.md, or other docs as needed
2. **Test Thoroughly**: Test on simulator and device if possible
3. **Check Code Style**: Ensure code follows project standards
4. **Rebase on Main**: Make sure your branch is up to date with main

```bash
git checkout main
git pull origin main
git checkout feature/your-feature
git rebase main
```

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring
- [ ] Other (please describe)

## Testing
- [ ] Tested on iOS Simulator
- [ ] Tested on physical device
- [ ] Added/updated tests

## Screenshots (if applicable)
Add screenshots for UI changes

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings introduced
- [ ] Tests pass (if applicable)
```

### Review Process

1. Maintainers will review your PR
2. Address any feedback or requested changes
3. Once approved, your PR will be merged

## Testing

### Manual Testing

- Test on iOS Simulator (various devices)
- Test on physical device if possible
- Test edge cases:
  - Empty states
  - Error conditions
  - Network failures
  - Large files
  - Multiple books

### Test Scenarios

**Import Flow**:
- Import from local files
- Import from Google Drive
- Handle import errors gracefully

**Playback**:
- Play, pause, seek
- Skip forward/backward
- Speed adjustment
- Position persistence

**Library Management**:
- Add books
- Delete books
- View book details

## Documentation

### Code Documentation

- Document public APIs
- Add comments for complex logic
- Use Swift documentation comments (`///`)

### User Documentation

- Update README.md for new features
- Update QUICK_START.md for setup changes
- Update GOOGLE_DRIVE_SETUP.md for Drive changes
- Update ARCHITECTURE.md for architectural changes

## Areas for Contribution

### High Priority

- [ ] CUE file parsing for chapter navigation
- [ ] Sleep timer implementation
- [ ] Unit tests
- [ ] UI/UX improvements
- [ ] Performance optimizations

### Medium Priority

- [ ] Playlist support
- [ ] Widget support
- [ ] CarPlay integration
- [ ] Accessibility improvements
- [ ] Localization support

### Low Priority

- [ ] Dark mode enhancements
- [ ] Custom themes
- [ ] Advanced playback features
- [ ] Analytics (privacy-focused)

## Questions?

- Open an issue for bugs or feature requests
- Ask questions in issue discussions
- Check existing issues before creating new ones

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to AudioBook Player! 🎉








