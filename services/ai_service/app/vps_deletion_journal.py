"""Durable local receipts for the explicitly selected, non-restorable VPS pilot."""

from __future__ import annotations

import asyncio
import os
import stat
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

from app.account_deletion_journal import (
    DeletionJournalEnvelope,
    DeletionJournalError,
    DeletionJournalReceipt,
)


class VpsFileDeletionJournalWriter:
    """Private disk persistence, not WORM or protection from a compromised API."""

    def __init__(
        self,
        directory: str,
        *,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._directory = Path(directory)
        self._now = now or (lambda: datetime.now(UTC))
        # Missing storage is an error, including after a lost/replaced VPS disk.
        # Only the administrator provisions this directory; startup never does.
        with self._open_directory():
            pass

    @contextmanager
    def _open_directory(self) -> Iterator[int]:
        descriptor = None
        try:
            if (
                not self._directory.is_absolute()
                or self._directory.resolve(strict=True) != self._directory
            ):
                raise DeletionJournalError(
                    "Journal directory must be an existing absolute path."
                )
            descriptor = os.open(
                self._directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
            )
            info = os.fstat(descriptor)
            if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
                raise DeletionJournalError(
                    "Journal directory must be private and API-owned."
                )
            yield descriptor
        except OSError:
            raise DeletionJournalError(
                "VPS deletion journal storage is unavailable."
            ) from None
        finally:
            if descriptor is not None:
                os.close(descriptor)

    async def append(self, envelope: DeletionJournalEnvelope) -> DeletionJournalReceipt:
        # fsync must not block other requests on the event loop. Cancellation
        # may leave a durable receipt, which an identical retry can accept.
        return await asyncio.to_thread(self._append, envelope)

    def _append(self, envelope: DeletionJournalEnvelope) -> DeletionJournalReceipt:
        for value in (envelope.deletion_id, envelope.user_id):
            try:
                valid = str(UUID(value)) == value
            except (ValueError, AttributeError, TypeError):
                valid = False
            if not valid:
                raise DeletionJournalError("Deletion journal identity is invalid.")
        content = envelope.canonical_content()
        filename = f"{envelope.deletion_id}.json"
        with self._open_directory() as directory_fd:
            replayed = self._existing(directory_fd, filename, content)
            if not replayed:
                temporary = f".pending-{uuid4().hex}"
                descriptor = os.open(
                    temporary,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                    0o600,
                    dir_fd=directory_fd,
                )
                try:
                    with os.fdopen(descriptor, "wb") as handle:
                        os.fchmod(handle.fileno(), 0o600)
                        handle.write(content)
                        handle.flush()
                        os.fsync(handle.fileno())
                    try:
                        # link publishes complete bytes without replacing an
                        # existing receipt, even when two retries race.
                        os.link(
                            temporary,
                            filename,
                            src_dir_fd=directory_fd,
                            dst_dir_fd=directory_fd,
                            follow_symlinks=False,
                        )
                    except FileExistsError:
                        replayed = self._existing(directory_fd, filename, content)
                        if not replayed:
                            raise DeletionJournalError(
                                "Deletion journal publication conflicted."
                            ) from None
                finally:
                    os.unlink(temporary, dir_fd=directory_fd)
            # Also sync an existing entry: a previous attempt might have lost
            # its acknowledgement or failed after link but before directory sync.
            os.fsync(directory_fd)
            # Initial administrator provisioning may be recent: persist the
            # journal directory's own entry in its parent as well.
            parent_fd = os.open("..", os.O_RDONLY | os.O_DIRECTORY, dir_fd=directory_fd)
            try:
                os.fsync(parent_fd)
            finally:
                os.close(parent_fd)
        return DeletionJournalReceipt(
            object_key=envelope.object_key(),
            payload_sha256=envelope.payload_sha256(),
            journaled_at=self._now(),
            replayed=replayed,
        )

    @staticmethod
    def _existing(directory_fd: int, filename: str, content: bytes) -> bool:
        try:
            descriptor = os.open(
                filename,
                os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                dir_fd=directory_fd,
            )
        except FileNotFoundError:
            return False
        try:
            info = os.fstat(descriptor)
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.geteuid()
                or stat.S_IMODE(info.st_mode) != 0o600
                or info.st_size != len(content)
                or os.read(descriptor, len(content) + 1) != content
            ):
                raise DeletionJournalError(
                    "Existing deletion receipt is invalid or conflicts."
                )
            os.fsync(descriptor)
            return True
        finally:
            os.close(descriptor)
