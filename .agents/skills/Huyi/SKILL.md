```markdown
# Huyi Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches you the core development patterns and conventions used in the Huyi repository, a C# codebase with no detected framework. You'll learn about file naming, import/export styles, commit patterns, and how to work with tests. This guide is ideal for onboarding new contributors or maintaining consistency across the project.

## Coding Conventions

### File Naming
- **Convention:** PascalCase for all files.
- **Example:**  
  ```
  MyClass.cs
  UserManager.cs
  ```

### Import Style
- **Convention:** Use relative imports within the project.
- **Example:**  
  ```csharp
  using MyNamespace.Utilities;
  ```

### Export Style
- **Convention:** Use named exports (public classes, methods, etc.).
- **Example:**  
  ```csharp
  public class UserManager
  {
      public void AddUser(User user) { ... }
  }
  ```

### Commit Patterns
- **Type:** Freeform messages, often prefixed with context (e.g., `windows`)
- **Average Length:** ~53 characters
- **Example:**  
  ```
  windows: fix file path issue on load
  ```

## Workflows

### Code Contribution
**Trigger:** When adding new features or fixing bugs  
**Command:** `/contribute`

1. Create a new branch for your feature or fix.
2. Follow PascalCase for all new file names.
3. Use relative imports for referencing other files.
4. Export classes and methods using named (public) exports.
5. Write a clear commit message, optionally prefixed (e.g., `windows:`).
6. Submit a pull request for review.

### Testing
**Trigger:** When writing or running tests  
**Command:** `/test`

1. Create test files using the `*.test.*` pattern (e.g., `UserManager.test.cs`).
2. Use the project's preferred (unknown) testing framework.
3. Ensure tests cover both typical and edge cases.
4. Run tests before pushing changes.

## Testing Patterns

- **Test File Naming:**  
  Use `*.test.*` in the filename, e.g., `UserManager.test.cs`.
- **Framework:**  
  Not specified; check with the team or project documentation.
- **Example:**  
  ```csharp
  // UserManager.test.cs
  [TestClass]
  public class UserManagerTests
  {
      [TestMethod]
      public void AddUser_ShouldIncreaseCount()
      {
          // Arrange
          var manager = new UserManager();
          var user = new User("Alice");

          // Act
          manager.AddUser(user);

          // Assert
          Assert.AreEqual(1, manager.UserCount);
      }
  }
  ```

## Commands
| Command      | Purpose                                   |
|--------------|-------------------------------------------|
| /contribute  | Start the code contribution workflow      |
| /test        | Run or write tests using project patterns |
```
