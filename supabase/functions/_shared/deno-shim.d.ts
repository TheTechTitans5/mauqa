// Type shim so `tsc` can check Edge Functions without the Deno toolchain. Deno provides the real implementation.
declare namespace Deno {
  function serve(handler: (req: Request) => Response | Promise<Response>): unknown;
  const env: { get(key: string): string | undefined };
}
