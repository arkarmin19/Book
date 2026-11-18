import type { ApiErrorCode } from "./response";

/**
 * Maps PostgreSQL / Supabase errors to the API error envelope.
 *
 * The booking functions (supabase/migrations/*_booking_functions.sql) raise
 * custom SQLSTATE codes BF001–BF015 with user-friendly messages. Supabase
 * returns the SQLSTATE in `error.code` and the text in `error.message`.
 */

export type DbErrorLike = { code?: string | null; message?: string | null };

export type MappedDbError = {
  code: ApiErrorCode;
  /** Stable machine-readable reason, e.g. "slot_taken". */
  reason: string;
  message: string;
  status: number;
};

type Rule = { code: ApiErrorCode; status: number; reason: string; showDbMessage: boolean; fallback: string };

const RULES: Record<string, Rule> = {
  BF001: { code: "UNAUTHENTICATED", status: 401, reason: "not_authenticated", showDbMessage: true, fallback: "Please log in." },
  BF002: { code: "NOT_FOUND", status: 404, reason: "service_unavailable", showDbMessage: true, fallback: "This service is not available." },
  BF003: { code: "UNPROCESSABLE", status: 422, reason: "business_inactive", showDbMessage: true, fallback: "This business is not accepting bookings." },
  BF004: { code: "UNPROCESSABLE", status: 422, reason: "staff_not_eligible", showDbMessage: true, fallback: "This staff member does not offer this service." },
  BF005: { code: "UNPROCESSABLE", status: 422, reason: "start_in_past", showDbMessage: true, fallback: "This time is in the past." },
  BF006: { code: "UNPROCESSABLE", status: 422, reason: "start_not_on_grid", showDbMessage: true, fallback: "Appointments start on the hour or half hour." },
  BF007: { code: "UNPROCESSABLE", status: 422, reason: "outside_working_hours", showDbMessage: true, fallback: "This time is outside working hours." },
  BF008: { code: "UNPROCESSABLE", status: 422, reason: "staff_unavailable", showDbMessage: true, fallback: "The staff member is unavailable at this time." },
  BF009: { code: "CONFLICT", status: 409, reason: "slot_taken", showDbMessage: true, fallback: "This time slot has just been booked. Please choose another time." },
  BF010: { code: "NOT_FOUND", status: 404, reason: "booking_not_found", showDbMessage: true, fallback: "Booking not found." },
  BF011: { code: "FORBIDDEN", status: 403, reason: "forbidden", showDbMessage: true, fallback: "You are not allowed to do this." },
  BF012: { code: "UNPROCESSABLE", status: 422, reason: "cutoff_passed", showDbMessage: true, fallback: "This booking can no longer be changed online." },
  BF013: { code: "UNPROCESSABLE", status: 422, reason: "invalid_status", showDbMessage: true, fallback: "This booking cannot be changed in its current state." },
  BF014: { code: "UNPROCESSABLE", status: 422, reason: "too_far_ahead", showDbMessage: true, fallback: "Bookings can be made up to 180 days ahead." },
  BF015: { code: "VALIDATION_ERROR", status: 400, reason: "invalid_input", showDbMessage: true, fallback: "Invalid input." },

  // Standard PostgreSQL codes. Their raw messages can expose table/constraint
  // names, so a generic message is returned instead (except where we wrote it).
  "23P01": { code: "CONFLICT", status: 409, reason: "slot_taken", showDbMessage: false, fallback: "This time slot has just been booked. Please choose another time." },
  "23505": { code: "CONFLICT", status: 409, reason: "duplicate", showDbMessage: false, fallback: "This already exists." },
  "23503": { code: "UNPROCESSABLE", status: 422, reason: "related_record", showDbMessage: false, fallback: "This record is linked to other data and cannot be changed this way." },
  "23514": { code: "VALIDATION_ERROR", status: 400, reason: "check_failed", showDbMessage: false, fallback: "Some values are invalid." },
  "22023": { code: "VALIDATION_ERROR", status: 400, reason: "invalid_parameter", showDbMessage: true, fallback: "Invalid value." },
  "42501": { code: "FORBIDDEN", status: 403, reason: "forbidden", showDbMessage: false, fallback: "You are not allowed to do this." },
};

const INTERNAL: Rule = {
  code: "INTERNAL_ERROR",
  status: 500,
  reason: "internal_error",
  showDbMessage: false,
  fallback: "Something went wrong. Please try again.",
};

export function mapDbError(error: DbErrorLike): MappedDbError {
  const rule = (error.code && RULES[error.code]) || INTERNAL;
  const message = rule.showDbMessage && error.message ? error.message : rule.fallback;
  return { code: rule.code, reason: rule.reason, message, status: rule.status };
}

/** True when the error means "someone else got this slot first" (refresh slots). */
export function isSlotConflict(error: DbErrorLike): boolean {
  return error.code === "BF009" || error.code === "23P01";
}
