# Add simde library in third-party

**Status:** Not started
**Priority:** P1 (High)

## Overview

Could you please add the simde library https://github.com/simd-everywhere/simde in third-party libraries for TheRock. This would be an input dependency for both hip-runtime and rocr-runtime. Missing this library is currently blocking these two PRs as the TheRock-CI build check is now set to required:
ROCm/rocm-systems#500
ROCm/rocm-systems#1752

## Goals

- [ ] Add the simde library to TheRock/third-party
- [ ] Add as a dep to ROCR-Runtime
- [ ] Add as a dep to clr
- [ ] Make sure that the project builds without error up through clr

## Context

