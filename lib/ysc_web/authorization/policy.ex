defmodule YscWeb.Authorization.Policy do
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
end
