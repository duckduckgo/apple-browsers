# iOS browser dependencies

- Do not add uses of `AppDependencyProvider`, including singleton lookups and
  initializer default arguments. Inject the specific dependency or reuse one
  already owned by the type. Existing accesses are legacy, not examples to copy.
