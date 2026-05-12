module Admin::UsersHelper
  def delete_block_reason(user)
    return "Cannot delete yourself!" if user == current_user
    return "Cannot delete admins!" if user.admin?

    nil
  end
end
