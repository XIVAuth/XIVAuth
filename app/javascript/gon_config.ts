import { GonNamespace } from "./gon_namespace";

export const GonConfig = {
  UserPreferences<T extends object>() {
    const data = window.gon.user_preferences ?? {};
    return new GonNamespace<T>(data);
  },
};