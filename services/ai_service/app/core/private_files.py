import asyncio
import shutil
import stat
from collections.abc import Awaitable
from pathlib import Path
from typing import TypeVar


class PrivateFileCleanupError(RuntimeError):
    pass


_Result = TypeVar("_Result")


def remove_private_directory(
    path: Path,
    *,
    expected_name_prefix: str,
) -> None:
    """Remove one known temporary directory without following replacement links."""

    if (
        not path.is_absolute()
        or path.parent == path
        or not expected_name_prefix
        or not path.name.startswith(expected_name_prefix)
    ):
        raise PrivateFileCleanupError(
            "Private temporary data cleanup target was invalid.",
        )

    last_error: OSError | None = None
    for _attempt in range(2):
        try:
            metadata = path.lstat()
        except FileNotFoundError:
            return
        except OSError as exc:
            last_error = exc
            continue

        try:
            if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(
                metadata.st_mode,
            ):
                shutil.rmtree(path)
            else:
                path.unlink()
        except FileNotFoundError:
            return
        except OSError as exc:
            last_error = exc

        try:
            path.lstat()
        except FileNotFoundError:
            return
        except OSError as exc:
            last_error = exc

    raise PrivateFileCleanupError(
        "Private temporary data could not be removed.",
    ) from last_error


async def await_despite_cancellation(awaitable: Awaitable[_Result]) -> _Result:
    """Finish security cleanup before propagating cancellation to the caller."""

    task = asyncio.ensure_future(awaitable)
    current = asyncio.current_task()
    cancellation: asyncio.CancelledError | None = None
    while not task.done():
        try:
            await asyncio.shield(task)
        except asyncio.CancelledError as exc:
            cancellation = exc
            # A Task retains its cancellation count after CancelledError is
            # caught. Consume this request while cleanup runs, then propagate
            # the captured cancellation only after the cleanup task finishes.
            if current is not None and current.cancelling():
                current.uncancel()
    result = task.result()
    if cancellation is not None:
        raise cancellation
    return result


async def remove_private_directory_despite_cancellation(
    path: Path,
    *,
    expected_name_prefix: str,
) -> None:
    # This deliberately has no suspension point: once entered, a Task
    # cancellation cannot interrupt deletion or its absence verification.
    remove_private_directory(
        path,
        expected_name_prefix=expected_name_prefix,
    )
