import { describe, expect, it } from "vitest";

import { isSlotConflict, mapDbError } from "@/lib/api/db-errors";

describe("mapDbError", () => {
  it("maps a booking conflict to 409 with the database message", () => {
    const mapped = mapDbError({ code: "BF009", message: "This time slot has just been booked." });
    expect(mapped).toEqual({
      code: "CONFLICT",
      reason: "slot_taken",
      status: 409,
      message: "This time slot has just been booked.",
    });
  });

  it("maps a raw exclusion violation to 409 without leaking constraint names", () => {
    const mapped = mapDbError({
      code: "23P01",
      message: 'conflicting key value violates exclusion constraint "bookings_no_overlap"',
    });
    expect(mapped.status).toBe(409);
    expect(mapped.message).not.toContain("bookings_no_overlap");
  });

  it.each([
    ["BF001", 401],
    ["BF002", 404],
    ["BF005", 422],
    ["BF006", 422],
    ["BF007", 422],
    ["BF010", 404],
    ["BF011", 403],
    ["BF012", 422],
    ["BF015", 400],
    ["42501", 403],
  ])("maps %s to HTTP %i", (code, status) => {
    expect(mapDbError({ code, message: "x" }).status).toBe(status);
  });

  it("hides the message of permission errors", () => {
    const mapped = mapDbError({ code: "42501", message: 'permission denied for table "bookings"' });
    expect(mapped.message).toBe("You are not allowed to do this.");
  });

  it("falls back to 500 for unknown codes", () => {
    expect(mapDbError({ code: "XX000", message: "boom" })).toMatchObject({ status: 500, code: "INTERNAL_ERROR" });
    expect(mapDbError({}).status).toBe(500);
  });
});

describe("isSlotConflict", () => {
  it("recognises both conflict codes", () => {
    expect(isSlotConflict({ code: "BF009" })).toBe(true);
    expect(isSlotConflict({ code: "23P01" })).toBe(true);
    expect(isSlotConflict({ code: "BF007" })).toBe(false);
  });
});
