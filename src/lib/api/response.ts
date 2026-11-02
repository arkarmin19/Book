import { NextResponse } from "next/server";

/**
 * Consistent API response envelope used by every Route Handler.
 *
 *   success: { "data": ... }
 *   failure: { "error": { "code": "...", "message": "...", "details"?: ... } }
 */

export type ApiErrorCode =
  | "BAD_REQUEST"
  | "VALIDATION_ERROR"
  | "UNAUTHENTICATED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "UNPROCESSABLE"
  | "SERVICE_UNAVAILABLE"
  | "INTERNAL_ERROR";

const STATUS_BY_CODE: Record<ApiErrorCode, number> = {
  BAD_REQUEST: 400,
  VALIDATION_ERROR: 400,
  UNAUTHENTICATED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  UNPROCESSABLE: 422,
  SERVICE_UNAVAILABLE: 503,
  INTERNAL_ERROR: 500,
};

export type ApiSuccess<T> = { data: T };
export type ApiFailure = { error: { code: ApiErrorCode; message: string; details?: unknown } };

export function ok<T>(data: T, init?: { status?: number; headers?: HeadersInit }) {
  return NextResponse.json<ApiSuccess<T>>({ data }, { status: init?.status ?? 200, headers: init?.headers });
}

export function fail(code: ApiErrorCode, message: string, details?: unknown) {
  const body: ApiFailure = { error: { code, message, ...(details === undefined ? {} : { details }) } };
  return NextResponse.json<ApiFailure>(body, { status: STATUS_BY_CODE[code] });
}

export function statusForCode(code: ApiErrorCode): number {
  return STATUS_BY_CODE[code];
}
