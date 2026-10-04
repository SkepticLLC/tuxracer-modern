# macOS Application Bundle

Tux Racer Modern keeps the command-line development executable and packages a separate self-contained macOS application.

Build:

```sh
./scripts/bootstrap-macos.sh
```

Package:

```sh
chmod +x scripts/package-macos.sh
./scripts/package-macos.sh
```

Launch:

```sh
open "build/Tux Racer Modern.app"
```

The bundle contains the executable under `Contents/MacOS` and original game data under `Contents/Resources/data`. Runtime data discovery recognizes that layout automatically.

Development bundles are ad-hoc signed. Public distribution will require an Apple Developer ID signature and notarization workflow; those are intentionally separate from local packaging.
