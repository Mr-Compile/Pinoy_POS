/// Result of restoring a persisted session.
///
/// [none]     : no persisted session was found.
/// [expired]  : the absolute session lifetime has passed.
/// [locked]   : the inactivity timeout has passed but the absolute lifetime
///              has not; the user should re-enter their PIN.
/// [active]   : both the inactivity and absolute lifetimes are still valid.
enum SessionStatus { none, expired, locked, active }
