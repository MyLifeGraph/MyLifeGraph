import asyncio
from pathlib import Path

import pytest

import app.core.private_files as private_files


def test_private_cleanup_finishes_before_propagating_cancellation() -> None:
    async def run() -> None:
        started = asyncio.Event()
        release = asyncio.Event()
        finished = False

        async def cleanup() -> None:
            nonlocal finished
            started.set()
            await release.wait()
            finished = True

        task = asyncio.create_task(
            private_files.await_despite_cancellation(cleanup()),
        )
        await started.wait()
        task.cancel()
        release.set()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert finished is True

    asyncio.run(run())


def test_private_directory_cleanup_is_verified_without_a_suspension_point(
    tmp_path: Path,
) -> None:
    working_directory = tmp_path / "mylifegraph-test-private"
    working_directory.mkdir()
    (working_directory / "personal.txt").write_text(
        "private",
        encoding="utf-8",
    )

    asyncio.run(
        private_files.remove_private_directory_despite_cancellation(
            working_directory,
            expected_name_prefix="mylifegraph-test-",
        ),
    )

    assert not working_directory.exists()
