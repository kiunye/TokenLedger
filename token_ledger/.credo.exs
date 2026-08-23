%{
  configs: [
    %{
      name: "default",
      # ExSlop: Credo checks that catch AI-generated "slop" (blanket rescues,
      # narrator docs, anti-idiomatic Enum usage, etc.). Registered as a plugin
      # so its checks auto-register — no manual cherry-picking of individual
      # checks. Credo's built-in checks still apply via its defaults.
      plugins: [{ExSlop, []}]
    }
  ]
}
