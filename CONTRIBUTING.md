# Contributing to OpenClaw Migration Tool

First off, thank you for considering contributing! 🎉

## Ways to Contribute

### 🐛 Report Bugs
- Check [existing issues](https://github.com/oxFFFF-Q/openclaw-migrate/issues) first
- Use the bug report template
- Include system info (`./openclaw-migrate.sh doctor` output)

### 💡 Suggest Features
- Open an issue with the "enhancement" label
- Describe the use case clearly

### 🔧 Submit Pull Requests

#### Development Setup
```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/openclaw-migrate.git
cd openclaw-migrate

# Make scripts executable
chmod +x openclaw-migrate.sh openclaw-migrate.ps1

# Test locally
./openclaw-migrate.sh doctor
```

#### Pull Request Guidelines
1. **Fork** the repository
2. **Create a branch**: `git checkout -b feature/my-feature`
3. **Make changes** and test thoroughly
4. **Commit**: Use clear commit messages
5. **Push**: `git push origin feature/my-feature`
6. **Open PR**: Describe changes and link any issues

#### Code Style
- **Shell**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- **PowerShell**: Follow [Microsoft PowerShell Best Practices](https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations)
- **Comments**: Document functions and complex logic
- **Testing**: Test on at least one platform before submitting

### 📚 Improve Documentation
- Fix typos or clarify instructions
- Add examples or use cases
- Translate to other languages

## Testing

### Test Matrix
| Platform | Test Command |
|----------|--------------|
| macOS | `./openclaw-migrate.sh doctor && ./openclaw-migrate.sh export --dry-run` |
| Linux | Same as macOS |
| Windows | `./openclaw-migrate.ps1 doctor` |

### Test Cases
1. Fresh system (no OpenClaw installed)
2. Existing OpenClaw installation
3. Import from exported archive
4. Each export mode (replicate/full/skills)
5. `--dry-run` flag

## Release Process

1. Update `VERSION` file
2. Update `CHANGELOG.md`
3. Create git tag: `git tag v1.x.x`
4. Push tag: `git push --tags`
5. GitHub Actions will create release

## Questions?

Open an [issue](https://github.com/oxFFFF-Q/openclaw-migrate/issues) or [discussion](https://github.com/oxFFFF-Q/openclaw-migrate/discussions).

---

**License**: MIT - See [LICENSE](LICENSE) file
