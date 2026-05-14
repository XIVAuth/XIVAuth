export class GonNamespace<T extends object> {
  constructor(private readonly data: Record<string, unknown>) {}

  get<K extends keyof T & string>(key: K): T[K] | undefined {
    return this.data[key] as T[K] | undefined;
  }

  getOrDefault<K extends keyof T & string>(key: K, fallback: NonNullable<T[K]>): NonNullable<T[K]> {
    return (this.data[key] ?? fallback) as NonNullable<T[K]>;
  }

  require<K extends keyof T & string>(key: K): NonNullable<T[K]> {
    const val = this.data[key];
    if (val == null) throw new Error(`[GonConfig] Missing required key: "${key}"`);
    return val as NonNullable<T[K]>;
  }

  has<K extends keyof T & string>(key: K): boolean {
    return key in this.data && this.data[key] != null;
  }
}
