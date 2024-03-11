import EctoEnum

defenum(UserAccountState, ["pending_approval", "rejected", "active", "suspended", "deleted"])
defenum(UserAccountRole, ["member", "admin"])
defenum(FamilyMemberType, ["spouse", "child"])
defenum(MembershipType, ["single", "family"])

defenum(MembershipEligibility, [
  "citizen_of_scandinavia",
  "born_in_scandinavia",
  "scandinavian_parent",
  "lived_in_scandinavia",
  "speak_scandinavian_language",
  "spouse_of_member"
])

defenum(SignupApplicationEventType, ["review_started", "review_completed", "review_updated"])
defenum(UserEventType, ["state_update", "role_update"])
