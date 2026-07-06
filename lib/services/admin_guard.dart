/// Source of an admin request.
enum RequestSource {
  /// The human user.
  user,

  /// An AI character acting on behalf of (or within) the system.
  character,
}

/// Result of an access-control check.
enum AccessDecision {
  /// Action may proceed immediately.
  granted,

  /// Action is forbidden.
  denied,

  /// Action requires explicit user approval via Core Hub.
  needsApproval,
}

/// A pending request to modify Core Hub rules or execute a privileged action.
class AdminRequest {
  /// Who is making the request.
  final RequestSource source;

  /// userId when [source] is [RequestSource.user], characterId otherwise.
  final String sourceId;

  /// The action being attempted, e.g.
  /// "modify_persona_rule", "toggle_new_world", "execute_social_action".
  final String targetAction;

  /// Optional ID of the character or resource being targeted.
  final String? targetId;

  /// Arbitrary payload attached to the request.
  final Map<String, dynamic>? payload;

  /// When the request was created.
  final DateTime timestamp;

  AdminRequest({
    required this.source,
    required this.sourceId,
    required this.targetAction,
    this.targetId,
    this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Stateless permission guard for Core Hub privileged operations.
///
/// Only the human user holds full admin rights. AI characters must go through
/// approval for most actions and are outright forbidden from modifying Core
/// Hub configuration.
class AdminGuard {
  /// Create a new [AdminGuard] instance (no external dependencies).
  AdminGuard();

  /// Evaluate [request] and return the appropriate [AccessDecision].
  ///
  /// - User requests are always granted.
  /// - Character requests that target Core Hub config are denied.
  /// - All other character requests require approval.
  AccessDecision checkAccess(AdminRequest request) {
    if (request.source == RequestSource.user) {
      return AccessDecision.granted;
    }

    // Character source from here onward.
    final action = request.targetAction;

    // Actions that modify Core Hub configuration are forbidden for characters.
    if (action.startsWith('config_') || action.startsWith('admin_')) {
      return AccessDecision.denied;
    }

    // Social / visit operations need approval (Core Hub checks persona rules).
    if (action.startsWith('social_') || action.startsWith('visit_')) {
      return AccessDecision.needsApproval;
    }

    // Every other character action also needs approval.
    return AccessDecision.needsApproval;
  }

  /// Returns `true` if [sourceId] matches [currentUserId].
  bool isAdmin(String sourceId, String? currentUserId) {
    if (currentUserId == null) return false;
    return sourceId == currentUserId;
  }

  /// Returns `true` if the caller identified by [sourceId] may modify Core
  /// Hub configuration. Only the human user has this privilege.
  bool canModifyCoreConfig(String sourceId, String? currentUserId) {
    return isAdmin(sourceId, currentUserId);
  }

  /// Returns `true` if [sourceId] can execute [action] without going through
  /// the approval flow.
  ///
  /// The user can execute anything directly; characters always need approval.
  bool canExecuteDirectly(
    String sourceId,
    String? currentUserId,
    String action,
  ) {
    return isAdmin(sourceId, currentUserId);
  }
}
