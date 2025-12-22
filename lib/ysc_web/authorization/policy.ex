defmodule YscWeb.Authorization.Policy do
  @moduledoc """
  Authorization policy definitions.

  Defines access control policies for various resources and actions using LetMe.
  """
  use LetMe.Policy

  object :post do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :user do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      deny true
    end
  end

  object :signup_application do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :media_image do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :site_setting do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :event do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :agenda do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :agenda_item do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :ticket_tier do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :family_invite do
    action :create do
      allow role: :admin
      allow :can_send_family_invite
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :revoke do
      allow role: :admin
      allow :own_resource
    end
  end

  object :family_sub_account do
    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :remove do
      allow role: :admin
      allow :own_resource
    end

    action :manage do
      allow role: :admin
      allow :own_resource
    end
  end
end
