export class SessionPool {
  #sessions = new Map();
  activeId = null;
  constructor(createRuntime) { this.createRuntime = createRuntime; }
  activate(device) {
    let runtime = this.#sessions.get(device.id);
    if (runtime && runtime.revision !== device.revision) {
      runtime.dispose();
      this.#sessions.delete(device.id);
      runtime = null;
    }
    if (!runtime) {
      const resource = this.createRuntime(device);
      runtime = { ...resource, revision: device.revision };
      this.#sessions.set(device.id, runtime);
    }
    this.activeId = device.id;
    for (const [id, session] of this.#sessions) session.setVisible(id === device.id);
    return runtime;
  }
  get(id) { return this.#sessions.get(id); }
  remove(id) {
    this.#sessions.get(id)?.dispose();
    this.#sessions.delete(id);
    if (this.activeId === id) this.activeId = null;
  }
  dispose() { for (const id of this.#sessions.keys()) this.remove(id); }
}
