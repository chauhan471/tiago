defmodule TiagoWeb.AuthLive.Register do
  use TiagoWeb, :live_view
  alias Tiago.Auth.User

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Register",
       form: to_form(User.registration_changeset(%User{}, %{}))
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50">
      <div class="bg-white p-8 rounded-xl shadow-lg w-full max-w-md">
        <h1 class="text-2xl font-bold text-center mb-6">Create Account</h1>
        <.form for={@form} action={~p"/session"} method="post" phx-change="validate" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Name</label>
            <.input field={@form[:name]} type="text" placeholder="Your name" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Email</label>
            <.input field={@form[:email]} type="email" placeholder="you@example.com" required />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Password</label>
            <.input field={@form[:password]} type="password" placeholder="Min 8 characters" required />
          </div>
          <input type="hidden" name="_action" value="register" />
          <button
            type="submit"
            class="w-full bg-blue-600 text-white rounded-lg py-2.5 font-medium hover:bg-blue-700 transition"
          >
            Create Account
          </button>
        </.form>
        <p class="text-center text-sm text-gray-600 mt-4">
          Already have an account?
          <.link navigate={~p"/login"} class="text-blue-600 hover:underline">Log in</.link>
        </p>
      </div>
    </div>
    """
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset = User.registration_changeset(%User{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset))}
  end
end
