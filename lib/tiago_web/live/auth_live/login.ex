defmodule TiagoWeb.AuthLive.Login do
  use TiagoWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Log In", email: "", password: "")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50">
      <div class="bg-white p-8 rounded-xl shadow-lg w-full max-w-md">
        <h1 class="text-2xl font-bold text-center mb-6">Log In</h1>
        <form action={~p"/session"} method="post" class="space-y-4">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Email</label>
            <input
              type="email"
              name="email"
              placeholder="you@example.com"
              required
              class="w-full rounded-lg border-gray-300"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Password</label>
            <input
              type="password"
              name="password"
              placeholder="Password"
              required
              class="w-full rounded-lg border-gray-300"
            />
          </div>
          <button
            type="submit"
            class="w-full bg-blue-600 text-white rounded-lg py-2.5 font-medium hover:bg-blue-700 transition"
          >
            Log In
          </button>
        </form>
        <p class="text-center text-sm text-gray-600 mt-4">
          Don't have an account?
          <.link navigate={~p"/register"} class="text-blue-600 hover:underline">Register</.link>
        </p>
      </div>
    </div>
    """
  end
end
