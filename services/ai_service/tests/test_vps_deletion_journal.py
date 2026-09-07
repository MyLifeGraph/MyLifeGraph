import asyncio
import errno
import os
import stat
import threading
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.account_deletion_journal import (
    DeletionJournalEnvelope,
    DeletionJournalError,
    InMemoryDeletionJournalWriter,
    deletion_journal_from_settings,
)
from app.core.config import Settings
from app.vps_deletion_journal import VpsFileDeletionJournalWriter


NOW = datetime(2026, 9, 7, 12, tzinfo=UTC)
ENVELOPE = DeletionJournalEnvelope(
    deletion_id="11111111-2222-4333-8444-555555555555",
    user_id="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
    accepted_at=NOW,
)


@pytest.fixture
def directory(tmp_path: Path) -> Path:
    path = tmp_path / "journal"
    path.mkdir(mode=0o700)
    return path


def writer(directory: Path) -> VpsFileDeletionJournalWriter:
    return VpsFileDeletionJournalWriter(str(directory), now=lambda: NOW)


def test_receipt_is_private_durable_and_identical_after_restart(directory, monkeypatch):
    synced = []
    real_sync = os.fsync

    def observed_sync(fd):
        synced.append(stat.S_ISDIR(os.fstat(fd).st_mode))
        real_sync(fd)

    monkeypatch.setattr(os, "fsync", observed_sync)
    first = asyncio.run(writer(directory).append(ENVELOPE))
    receipt_file = directory / f"{ENVELOPE.deletion_id}.json"
    assert receipt_file.read_bytes() == ENVELOPE.canonical_content()
    assert stat.S_IMODE(receipt_file.stat().st_mode) == 0o600
    assert list(directory.iterdir()) == [receipt_file]
    assert synced == [False, True, True]
    assert first.object_key == ENVELOPE.object_key()
    assert first.payload_sha256 == ENVELOPE.payload_sha256()
    assert not first.replayed
    second = asyncio.run(writer(directory).append(ENVELOPE))
    assert second.replayed
    assert second.payload_sha256 == first.payload_sha256
    assert synced == [False, True, True, False, True, True]


def test_concurrent_identical_retries_publish_one_receipt(directory):
    async def race():
        return await asyncio.gather(
            *(writer(directory).append(ENVELOPE) for _ in range(12))
        )

    results = asyncio.run(race())
    assert sum(not item.replayed for item in results) == 1
    assert len(list(directory.iterdir())) == 1
    assert len({item.payload_sha256 for item in results}) == 1


def test_conflicting_retry_does_not_overwrite_receipt(directory):
    asyncio.run(writer(directory).append(ENVELOPE))
    conflict = replace(ENVELOPE, user_id="bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    with pytest.raises(DeletionJournalError, match="conflicts"):
        asyncio.run(writer(directory).append(conflict))
    assert (
        directory / f"{ENVELOPE.deletion_id}.json"
    ).read_bytes() == ENVELOPE.canonical_content()


@pytest.mark.parametrize("sync_number", [1, 2, 3])
def test_sync_failure_never_acknowledges_and_retry_recovers(
    directory, monkeypatch, sync_number
):
    real_sync = os.fsync
    calls = 0

    def failed_sync(fd):
        nonlocal calls
        calls += 1
        if calls == sync_number:
            raise OSError(errno.EIO, "injected disk failure")
        real_sync(fd)

    with monkeypatch.context() as scoped:
        scoped.setattr(os, "fsync", failed_sync)
        with pytest.raises(DeletionJournalError, match="unavailable"):
            asyncio.run(writer(directory).append(ENVELOPE))
    assert not list(directory.glob(".pending-*"))
    result = asyncio.run(writer(directory).append(ENVELOPE))
    # A failed directory sync can leave a complete but unacknowledged receipt.
    assert result.replayed is (sync_number >= 2)
    assert (
        directory / f"{ENVELOPE.deletion_id}.json"
    ).read_bytes() == ENVELOPE.canonical_content()


def test_full_disk_at_publication_does_not_acknowledge_or_leave_partial_receipt(
    directory, monkeypatch
):
    def full_disk(*args, **kwargs):
        raise OSError(errno.ENOSPC, "injected full disk")

    with monkeypatch.context() as scoped:
        scoped.setattr(os, "link", full_disk)
        with pytest.raises(DeletionJournalError):
            asyncio.run(writer(directory).append(ENVELOPE))
    assert not list(directory.iterdir())
    assert not asyncio.run(writer(directory).append(ENVELOPE)).replayed


def test_crash_before_publication_leaves_no_receipt_and_retry_is_safe(directory):
    process = os.fork()
    if process == 0:
        os.link = lambda *args, **kwargs: os._exit(17)
        writer(directory)._append(ENVELOPE)
        os._exit(1)
    _, status = os.waitpid(process, 0)
    assert os.waitstatus_to_exitcode(status) == 17
    assert list(directory.glob(".pending-*"))
    assert not list(directory.glob("*.json"))
    assert not asyncio.run(writer(directory).append(ENVELOPE)).replayed
    assert len(list(directory.glob("*.json"))) == 1


@pytest.mark.parametrize(
    "kind", ["symlink", "fifo", "directory", "public_file", "corrupt"]
)
def test_invalid_existing_entry_is_never_accepted(directory, tmp_path, kind):
    entry = directory / f"{ENVELOPE.deletion_id}.json"
    if kind == "symlink":
        target = tmp_path / "other"
        target.write_bytes(ENVELOPE.canonical_content())
        entry.symlink_to(target)
    elif kind == "fifo":
        os.mkfifo(entry, 0o600)
    elif kind == "directory":
        entry.mkdir()
    else:
        entry.write_bytes(
            ENVELOPE.canonical_content() if kind == "public_file" else b"partial"
        )
        entry.chmod(0o644 if kind == "public_file" else 0o600)
    with pytest.raises(DeletionJournalError):
        asyncio.run(writer(directory).append(ENVELOPE))


def test_storage_is_never_created_or_repaired_implicitly(directory, tmp_path):
    with pytest.raises(DeletionJournalError):
        writer(directory / "missing")
    assert not (directory / "missing").exists()
    directory.chmod(0o750)
    with pytest.raises(DeletionJournalError):
        writer(directory)
    directory.chmod(0o700)
    alias = tmp_path / "alias"
    alias.symlink_to(directory, target_is_directory=True)
    with pytest.raises(DeletionJournalError):
        writer(alias)
    existing = writer(directory)
    directory.rmdir()
    with pytest.raises(DeletionJournalError):
        asyncio.run(existing.append(ENVELOPE))
    assert not directory.exists()


def test_invalid_identity_cannot_escape_directory(directory):
    with pytest.raises(DeletionJournalError, match="identity"):
        asyncio.run(
            writer(directory).append(replace(ENVELOPE, deletion_id="../escape"))
        )
    assert not list(directory.iterdir())


def test_backend_selection_is_explicit_and_has_no_hosted_fallback(directory):
    settings = Settings(
        _env_file=None,
        APP_ENV="pilot",
        ACCOUNT_DELETION_JOURNAL_BACKEND="vps_file",
        ACCOUNT_DELETION_JOURNAL_DIRECTORY=str(directory),
    )
    assert isinstance(
        deletion_journal_from_settings(settings), VpsFileDeletionJournalWriter
    )
    with pytest.raises(DeletionJournalError):
        deletion_journal_from_settings(
            settings.model_copy(update={"account_deletion_journal_directory": ""})
        )
    with pytest.raises(ValueError, match="configuration"):
        deletion_journal_from_settings(Settings(_env_file=None, APP_ENV="pilot"))
    with pytest.raises(ValidationError):
        Settings(_env_file=None, ACCOUNT_DELETION_JOURNAL_BACKEND="vps-file")
    assert isinstance(
        deletion_journal_from_settings(Settings(_env_file=None)),
        InMemoryDeletionJournalWriter,
    )


def test_crash_after_publication_before_directory_sync_retries_existing_receipt(
    directory,
):
    process = os.fork()
    if process == 0:
        real_sync = os.fsync

        def crash_on_directory(fd):
            if stat.S_ISDIR(os.fstat(fd).st_mode):
                os._exit(19)
            real_sync(fd)

        os.fsync = crash_on_directory
        writer(directory)._append(ENVELOPE)
        os._exit(1)
    _, status = os.waitpid(process, 0)
    assert os.waitstatus_to_exitcode(status) == 19
    assert not list(directory.glob(".pending-*"))
    assert asyncio.run(writer(directory).append(ENVELOPE)).replayed
    assert len(list(directory.iterdir())) == 1


def test_cancelled_waiter_can_retry_a_receipt_finished_by_its_worker(
    directory, monkeypatch
):
    started, proceed, finished = threading.Event(), threading.Event(), threading.Event()
    journal = writer(directory)
    original_append = journal._append
    real_sync = os.fsync

    def blocked_sync(fd):
        if not started.is_set():
            started.set()
            assert proceed.wait(5)
        real_sync(fd)

    def observed_append(envelope):
        try:
            return original_append(envelope)
        finally:
            finished.set()

    monkeypatch.setattr(os, "fsync", blocked_sync)
    monkeypatch.setattr(journal, "_append", observed_append)

    async def cancel_then_retry():
        task = asyncio.create_task(journal.append(ENVELOPE))
        try:
            assert await asyncio.to_thread(started.wait, 5)
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
        finally:
            proceed.set()
        assert await asyncio.to_thread(finished.wait, 5)
        assert (await journal.append(ENVELOPE)).replayed

    asyncio.run(cancel_then_retry())
    assert len(list(directory.iterdir())) == 1


def test_receipt_mode_does_not_depend_on_inherited_umask(directory):
    previous = os.umask(0o777)
    try:
        asyncio.run(writer(directory).append(ENVELOPE))
    finally:
        os.umask(previous)
    entry = directory / f"{ENVELOPE.deletion_id}.json"
    assert stat.S_IMODE(entry.stat().st_mode) == 0o600
    assert asyncio.run(writer(directory).append(ENVELOPE)).replayed
