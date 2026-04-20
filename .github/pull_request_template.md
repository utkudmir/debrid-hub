## Summary

-

## Scope

- [ ] Change stays within current project boundary
- [ ] No forbidden endpoint integrations (`/unrestrict/*`, `/downloads/*`, `/torrents/*`, `/streaming/*`)

## Validation

- [ ] `make shared-test`
- [ ] Android checks pass for affected code
- [ ] iOS checks pass for affected code
- [ ] `make verify-rc` run when release-gate relevant
- [ ] `CONTRIBUTING.md` read and followed
- [ ] Security impact assessed (or N/A)

## Cross-Platform Impact

- [ ] Android behavior reviewed
- [ ] iOS behavior reviewed

## Docs

- [ ] README/docs updated if behavior or policy changed

## Localization

- [ ] Canonical YAML localization source updated when strings changed
- [ ] Generated Android/iOS/shared localization outputs refreshed
- [ ] `make localization-check` passes
- [ ] Native-speaker review status documented (or N/A)
- [ ] Store metadata impact assessed (or N/A)
- [ ] Screenshots included when translated UI copy materially changed
