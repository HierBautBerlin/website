[
  tools: [
    {:npm_test, false},
    {:typescript, "npm run typecheck", cd: "assets"},
    {:package_lock, "bin/check_package_lock.sh"}
  ]
]
