# Nomadcxx shared GitHub configuration

Nomadcxx uses this repository for organization defaults and shared CI workflows. [MATRIX.md](MATRIX.md) records the project set, default branches, release shapes, package channels, license surfaces, and current workflow state.

Run the matrix checks before changing its scope:

```sh
go test ./matrix
scripts/check-matrix-live.sh
```

Current and planned DEB/RPM output is limited to `sysc-greet`, `gSlapper`, and `sysc-Go`. `sysc-Go` keeps its project-owned release workflow. Published `sysc-walls` packages remain on historical releases; future releases do not attach new DEB/RPM files.
