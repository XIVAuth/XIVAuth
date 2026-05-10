import { Controller } from "@hotwired/stimulus";

export default class ToggleCategoryController extends Controller {
  static targets = ["item"]
  static values = { mode: { type: String, default: "disable" } }

  declare readonly itemTargets: HTMLInputElement[];
  declare readonly modeValue: string;

  connect() {
    this.refresh();
  }

  update(event: Event) {
    const toggle = event.currentTarget as HTMLInputElement;
    const category = toggle.dataset.category;
    if (!category) return;

    if (toggle.type === "radio") {
      this.itemTargets.forEach(el => this.deactivate(el));
      this.itemsForCategory(category).forEach(el => this.activate(el));
    } else if (toggle.type === "checkbox") {
      const action = toggle.checked ? this.activate : this.deactivate;
      this.itemsForCategory(category).forEach(el => action.call(this, el));
    }
  }

  private refresh() {
    this.itemTargets.forEach(el => this.deactivate(el));
    this.element.querySelectorAll<HTMLInputElement>("input[type='radio']:checked, input[type='checkbox']:checked")
      .forEach(toggle => {
        if (toggle.dataset.category) {
          this.itemsForCategory(toggle.dataset.category).forEach(el => this.activate(el));
        }
      });
  }

  private activate(el: HTMLInputElement) {
    if (this.modeValue === "hide") {
      el.classList.remove("d-none");
    } else {
      el.disabled = false;
    }
  }

  private deactivate(el: HTMLInputElement) {
    if (this.modeValue === "hide") {
      el.classList.add("d-none");
    } else {
      el.disabled = true;
    }
  }

  private itemsForCategory(category: string): HTMLInputElement[] {
    return this.itemTargets.filter(el => el.dataset.category === category);
  }
}
