defmodule Electricbrain.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Electricbrain.Accounts.User,
        _opts,
        _context
      ),
      do: Application.fetch_env(:electricbrain, :token_signing_secret)

  def secret_for(
        [:authentication, :strategies, :auth0, key],
        Electricbrain.Accounts.User,
        _opts,
        _context
      )
      when key in [:client_id, :client_secret, :base_url, :redirect_uri] do
    Application.fetch_env(:electricbrain, :"auth0_#{key}")
  end
end
