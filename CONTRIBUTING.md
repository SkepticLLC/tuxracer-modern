# Contributing to Tux Racer Modern

Thank you for helping preserve and continue Tux Racer.

## Ground rules
- Preserve original authorship, copyright and license notices.
- Keep platform/compatibility changes separate from gameplay changes where practical.
- Do not change physics merely to silence a compiler warning; explain and validate behavioral changes.
- Prefer portable core interfaces. Platform-specific Metal/Vulkan code belongs behind renderer/platform boundaries.
- Keep commits focused and buildable.
- New work must remain compatible with the project's open-source licensing obligations.

## Development flow
`main` should remain usable. Preservation milestones are tagged/branched. Significant renderer work should be developed on focused branches and merged through review once CI is green.

## Reporting issues
Include platform, architecture, OS version, build type, reproduction steps and relevant console/crash output. For rendering issues, screenshots are especially useful.
