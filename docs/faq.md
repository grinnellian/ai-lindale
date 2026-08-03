# FAQ

Short answers to questions that come up repeatedly. Each entry is
self-contained; add new entries as their own `##` section rather than folding
them into an existing one.

## Is a pod a devcontainer?

No. A pod ([docs/pod.md](pod.md)) is a container for devving in, not a
devcontainer. Three concrete differences:

- **No devcontainer.json spec.** A pod doesn't implement or read the
  [devcontainer specification](https://containers.dev/) — there's no
  `devcontainer.json`, no feature system, no lifecycle hooks defined by that
  spec.
- **No editor coupling.** A devcontainer is built around an editor attaching
  to it (VS Code Remote-Containers being the canonical case). A pod doesn't
  know or care whether an editor is attached. You can run VS Code against a
  pod if you want to, but nothing about the pod is designed for that — it's
  just a container that happens to have a shell.
- **The security boundary is the point.** A pod's distinguishing feature is
  that [moat](https://github.com/majorcontext/moat) injects credentials at
  the network layer, so tokens never enter the container. Devcontainers have
  no equivalent concept — credential handling isn't part of what a
  devcontainer is for.

The short version: devcontainer is an editor-integration spec, pod is a
security boundary. They're solving different problems and happen to both be
"a container you develop in."
