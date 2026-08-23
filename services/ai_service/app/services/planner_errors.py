class PlannerConflictError(RuntimeError):
    pass


class PlannerNotFoundError(RuntimeError):
    pass


class PlannerValidationError(ValueError):
    pass


class DeadlinePlanConflictError(RuntimeError):
    pass


class DeadlinePlanNotFoundError(RuntimeError):
    pass


class DeadlinePlanValidationError(ValueError):
    pass
