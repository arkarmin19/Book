
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "bookings": {
                  Row: {
                    "booking_reference": string,"business_id": string,"cancellation_reason": string | null,"cancelled_at": string | null,"cancelled_by": string | null,"created_at": string,"currency_snapshot": string,"customer_note": string | null,"customer_user_id": string,"during": unknown,"ends_at": string,"id": string,"price_snapshot": number,"reschedule_count": number,"service_id": string,"service_name_snapshot": string,"staff_user_id": string,"starts_at": string,"status": Database["public"]['Enums']["booking_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "booking_reference": string,"business_id": string,"cancellation_reason"?: string | null,"cancelled_at"?: string | null,"cancelled_by"?: string | null,"created_at"?: string,"currency_snapshot": string,"customer_note"?: string | null,"customer_user_id": string,"during"?: never,"ends_at": string,"id"?: string,"price_snapshot": number,"reschedule_count"?: number,"service_id": string,"service_name_snapshot": string,"staff_user_id": string,"starts_at": string,"status"?: Database["public"]['Enums']["booking_status"],"updated_at"?: string
                  }
                  Update: {
                    "booking_reference"?: string,"business_id"?: string,"cancellation_reason"?: string | null,"cancelled_at"?: string | null,"cancelled_by"?: string | null,"created_at"?: string,"currency_snapshot"?: string,"customer_note"?: string | null,"customer_user_id"?: string,"during"?: never,"ends_at"?: string,"id"?: string,"price_snapshot"?: number,"reschedule_count"?: number,"service_id"?: string,"service_name_snapshot"?: string,"staff_user_id"?: string,"starts_at"?: string,"status"?: Database["public"]['Enums']["booking_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "bookings_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bookings_cancelled_by_fkey"
      columns: ["cancelled_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bookings_customer_user_id_fkey"
      columns: ["customer_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "bookings_service_fkey"
      columns: ["business_id","service_id"]
isOneToOne: false
      referencedRelation: "services"
      referencedColumns: ["business_id","id"]
    },{
      foreignKeyName: "bookings_staff_fkey"
      columns: ["business_id","staff_user_id"]
isOneToOne: false
      referencedRelation: "business_members"
      referencedColumns: ["business_id","user_id"]
    }
                  ]
                },"business_members": {
                  Row: {
                    "avatar_path": string | null,"bio": string | null,"business_id": string,"created_at": string,"display_name": string,"id": string,"invited_by": string | null,"joined_at": string | null,"role": Database["public"]['Enums']["member_role"],"status": Database["public"]['Enums']["member_status"],"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "avatar_path"?: string | null,"bio"?: string | null,"business_id": string,"created_at"?: string,"display_name": string,"id"?: string,"invited_by"?: string | null,"joined_at"?: string | null,"role"?: Database["public"]['Enums']["member_role"],"status"?: Database["public"]['Enums']["member_status"],"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "avatar_path"?: string | null,"bio"?: string | null,"business_id"?: string,"created_at"?: string,"display_name"?: string,"id"?: string,"invited_by"?: string | null,"joined_at"?: string | null,"role"?: Database["public"]['Enums']["member_role"],"status"?: Database["public"]['Enums']["member_status"],"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "business_members_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "business_members_invited_by_fkey"
      columns: ["invited_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "business_members_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"businesses": {
                  Row: {
                    "address": string | null,"cancellation_cutoff_minutes": number,"created_at": string,"currency": string,"description": string | null,"email": string | null,"id": string,"is_active": boolean,"logo_path": string | null,"name": string,"owner_id": string,"phone": string | null,"slug": string,"timezone": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "address"?: string | null,"cancellation_cutoff_minutes"?: number,"created_at"?: string,"currency"?: string,"description"?: string | null,"email"?: string | null,"id"?: string,"is_active"?: boolean,"logo_path"?: string | null,"name": string,"owner_id": string,"phone"?: string | null,"slug": string,"timezone"?: string,"updated_at"?: string
                  }
                  Update: {
                    "address"?: string | null,"cancellation_cutoff_minutes"?: number,"created_at"?: string,"currency"?: string,"description"?: string | null,"email"?: string | null,"id"?: string,"is_active"?: boolean,"logo_path"?: string | null,"name"?: string,"owner_id"?: string,"phone"?: string | null,"slug"?: string,"timezone"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "businesses_owner_id_fkey"
      columns: ["owner_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"notification_logs": {
                  Row: {
                    "attempts": number,"booking_id": string,"business_id": string,"created_at": string,"error_message": string | null,"id": string,"last_attempt_at": string | null,"provider_message_id": string | null,"recipient_email": string,"status": Database["public"]['Enums']["notification_status"],"type": Database["public"]['Enums']["notification_type"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attempts"?: number,"booking_id": string,"business_id": string,"created_at"?: string,"error_message"?: string | null,"id"?: string,"last_attempt_at"?: string | null,"provider_message_id"?: string | null,"recipient_email": string,"status"?: Database["public"]['Enums']["notification_status"],"type": Database["public"]['Enums']["notification_type"],"updated_at"?: string
                  }
                  Update: {
                    "attempts"?: number,"booking_id"?: string,"business_id"?: string,"created_at"?: string,"error_message"?: string | null,"id"?: string,"last_attempt_at"?: string | null,"provider_message_id"?: string | null,"recipient_email"?: string,"status"?: Database["public"]['Enums']["notification_status"],"type"?: Database["public"]['Enums']["notification_type"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "notification_logs_booking_id_fkey"
      columns: ["booking_id"]
isOneToOne: false
      referencedRelation: "bookings"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "notification_logs_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    }
                  ]
                },"profiles": {
                  Row: {
                    "avatar_path": string | null,"created_at": string,"email": string,"full_name": string | null,"id": string,"phone": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "avatar_path"?: string | null,"created_at"?: string,"email": string,"full_name"?: string | null,"id": string,"phone"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "avatar_path"?: string | null,"created_at"?: string,"email"?: string,"full_name"?: string | null,"id"?: string,"phone"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"services": {
                  Row: {
                    "business_id": string,"created_at": string,"description": string | null,"duration_minutes": number,"id": string,"image_path": string | null,"is_active": boolean,"name": string,"price": number,"sort_order": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "business_id": string,"created_at"?: string,"description"?: string | null,"duration_minutes": number,"id"?: string,"image_path"?: string | null,"is_active"?: boolean,"name": string,"price": number,"sort_order"?: number,"updated_at"?: string
                  }
                  Update: {
                    "business_id"?: string,"created_at"?: string,"description"?: string | null,"duration_minutes"?: number,"id"?: string,"image_path"?: string | null,"is_active"?: boolean,"name"?: string,"price"?: number,"sort_order"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "services_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    }
                  ]
                },"staff_services": {
                  Row: {
                    "business_id": string,"created_at": string,"service_id": string,"staff_user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "business_id": string,"created_at"?: string,"service_id": string,"staff_user_id": string
                  }
                  Update: {
                    "business_id"?: string,"created_at"?: string,"service_id"?: string,"staff_user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "staff_services_member_fkey"
      columns: ["business_id","staff_user_id"]
isOneToOne: false
      referencedRelation: "business_members"
      referencedColumns: ["business_id","user_id"]
    },{
      foreignKeyName: "staff_services_service_fkey"
      columns: ["business_id","service_id"]
isOneToOne: false
      referencedRelation: "services"
      referencedColumns: ["business_id","id"]
    }
                  ]
                },"staff_time_off": {
                  Row: {
                    "business_id": string,"created_at": string,"created_by": string | null,"ends_at": string,"id": string,"reason": string | null,"staff_user_id": string | null,"starts_at": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "business_id": string,"created_at"?: string,"created_by"?: string | null,"ends_at": string,"id"?: string,"reason"?: string | null,"staff_user_id"?: string | null,"starts_at": string,"updated_at"?: string
                  }
                  Update: {
                    "business_id"?: string,"created_at"?: string,"created_by"?: string | null,"ends_at"?: string,"id"?: string,"reason"?: string | null,"staff_user_id"?: string | null,"starts_at"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "staff_time_off_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "staff_time_off_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "staff_time_off_member_fkey"
      columns: ["business_id","staff_user_id"]
isOneToOne: false
      referencedRelation: "business_members"
      referencedColumns: ["business_id","user_id"]
    }
                  ]
                },"staff_working_hours": {
                  Row: {
                    "business_id": string,"created_at": string,"end_time": string,"id": string,"staff_user_id": string,"start_time": string,"updated_at": string,"weekday": number
                  }
                  ComputedFields: never
                  Insert: {
                    "business_id": string,"created_at"?: string,"end_time": string,"id"?: string,"staff_user_id": string,"start_time": string,"updated_at"?: string,"weekday": number
                  }
                  Update: {
                    "business_id"?: string,"created_at"?: string,"end_time"?: string,"id"?: string,"staff_user_id"?: string,"start_time"?: string,"updated_at"?: string,"weekday"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "staff_working_hours_member_fkey"
      columns: ["business_id","staff_user_id"]
isOneToOne: false
      referencedRelation: "business_members"
      referencedColumns: ["business_id","user_id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "cancel_booking":
{ Args: { "p_booking_id": string,"p_reason"?: string }; Returns: {
              "booking_reference": string,
"business_id": string,
"cancellation_reason": string | null,
"cancelled_at": string | null,
"cancelled_by": string | null,
"created_at": string,
"currency_snapshot": string,
"customer_note": string | null,
"customer_user_id": string,
"during": unknown,
"ends_at": string,
"id": string,
"price_snapshot": number,
"reschedule_count": number,
"service_id": string,
"service_name_snapshot": string,
"staff_user_id": string,
"starts_at": string,
"status": Database["public"]['Enums']["booking_status"],
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "bookings"
        isOneToOne: true
        isSetofReturn: false
      } },
"create_booking":
{ Args: { "p_customer_note"?: string,"p_service_id": string,"p_staff_user_id"?: string,"p_starts_at": string }; Returns: {
              "booking_reference": string,
"business_id": string,
"cancellation_reason": string | null,
"cancelled_at": string | null,
"cancelled_by": string | null,
"created_at": string,
"currency_snapshot": string,
"customer_note": string | null,
"customer_user_id": string,
"during": unknown,
"ends_at": string,
"id": string,
"price_snapshot": number,
"reschedule_count": number,
"service_id": string,
"service_name_snapshot": string,
"staff_user_id": string,
"starts_at": string,
"status": Database["public"]['Enums']["booking_status"],
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "bookings"
        isOneToOne: true
        isSetofReturn: false
      } },
"reschedule_booking":
{ Args: { "p_booking_id": string,"p_new_staff_user_id"?: string,"p_new_starts_at": string }; Returns: {
              "booking_reference": string,
"business_id": string,
"cancellation_reason": string | null,
"cancelled_at": string | null,
"cancelled_by": string | null,
"created_at": string,
"currency_snapshot": string,
"customer_note": string | null,
"customer_user_id": string,
"during": unknown,
"ends_at": string,
"id": string,
"price_snapshot": number,
"reschedule_count": number,
"service_id": string,
"service_name_snapshot": string,
"staff_user_id": string,
"starts_at": string,
"status": Database["public"]['Enums']["booking_status"],
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "bookings"
        isOneToOne: true
        isSetofReturn: false
      } },
"timemultirange":
{ Args: Record<PropertyKey, never>; Returns: unknown
                           },
"update_booking_status":
{ Args: { "p_booking_id": string,"p_status": Database["public"]['Enums']["booking_status"] }; Returns: {
              "booking_reference": string,
"business_id": string,
"cancellation_reason": string | null,
"cancelled_at": string | null,
"cancelled_by": string | null,
"created_at": string,
"currency_snapshot": string,
"customer_note": string | null,
"customer_user_id": string,
"during": unknown,
"ends_at": string,
"id": string,
"price_snapshot": number,
"reschedule_count": number,
"service_id": string,
"service_name_snapshot": string,
"staff_user_id": string,
"starts_at": string,
"status": Database["public"]['Enums']["booking_status"],
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "bookings"
        isOneToOne: true
        isSetofReturn: false
      } }
          }
          Enums: {
            "booking_status": "pending"|"confirmed"|"cancelled"|"completed"|"no_show","member_role": "owner"|"manager"|"staff","member_status": "invited"|"active"|"inactive","notification_status": "queued"|"sent"|"failed","notification_type": "booking_created"|"booking_cancelled"|"booking_rescheduled"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "booking_status": ["pending", "confirmed", "cancelled", "completed", "no_show"],"member_role": ["owner", "manager", "staff"],"member_status": ["invited", "active", "inactive"],"notification_status": ["queued", "sent", "failed"],"notification_type": ["booking_created", "booking_cancelled", "booking_rescheduled"]
          }
        }
} as const
