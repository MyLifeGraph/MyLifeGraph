from collections.abc import Callable
from typing import Any, TypeVar

from fastapi import FastAPI


_DependencyT = TypeVar("_DependencyT")


def override_dependency(
    app: FastAPI,
    dependency: Callable[..., Any],
    value: _DependencyT,
) -> None:
    async def provide() -> _DependencyT:
        return value

    app.dependency_overrides[dependency] = provide
