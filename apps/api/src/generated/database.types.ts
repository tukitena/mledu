export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  api: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      apply_schedule_change: {
        Args: { p_change: Json; p_class_id: string; p_token: string }
        Returns: Json
      }
      archive_catalog_entry: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      archive_room: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      archive_site: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      auth_command_status: { Args: { p_command_id: string }; Returns: string }
      cancel_participation: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      class_lifecycle_impact: { Args: { p_id: string }; Returns: Json }
      clear_my_avatar: { Args: { p_expected_version: number }; Returns: Json }
      close_class: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      create_catalog_entry: { Args: { p_kind: string; p_name: string }; Returns: Json }
      create_class: {
        Args: {
          p_end_date: string
          p_grade_id: string
          p_name: string
          p_note?: string
          p_school_year_start?: number
          p_start_date: string
          p_subject_id: string
        }
        Returns: Json
      }
      create_class_assignment: {
        Args: {
          p_account_id: string
          p_class_id: string
          p_end_date: string
          p_role: string
          p_start_date: string
          p_subject_note?: string
        }
        Returns: Json
      }
      create_room: { Args: { p_name: string; p_site_id: string }; Returns: Json }
      create_site: { Args: { p_address: string; p_name: string }; Returns: Json }
      create_student: {
        Args: {
          p_birth_date?: string
          p_full_name: string
          p_general_note?: string
          p_parent_name?: string
          p_parent_phones?: string[]
          p_school?: string
          p_student_phones?: string[]
        }
        Returns: Json
      }
      current_session: {
        Args: { p_allow_password_change?: boolean }
        Returns: {
          account_id: string
          account_type: string
          must_change_password: boolean
        }[]
      }
      discard_avatar_upload: { Args: { p_path: string }; Returns: boolean }
      end_class_assignment: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      enroll_student: {
        Args: {
          p_class_id: string
          p_join_date: string
          p_leave_date?: string
          p_note?: string
          p_student_id: string
        }
        Returns: Json
      }
      get_account: { Args: { p_account_id: string }; Returns: Json }
      get_attendance: { Args: { p_session_id: string }; Returns: Json }
      get_class: { Args: { p_id: string }; Returns: Json }
      get_class_schedule: { Args: { p_class_id: string }; Returns: Json }
      get_my_profile: { Args: Record<PropertyKey, never>; Returns: Json }
      get_student: { Args: { p_id: string }; Returns: Json }
      health_check: { Args: Record<PropertyKey, never>; Returns: boolean }
      list_accounts: {
        Args: { p_limit?: number; p_offset?: number; p_search?: string; p_status?: string }
        Returns: Json
      }
      list_assignable_accounts: { Args: Record<PropertyKey, never>; Returns: Json }
      list_catalog_entries: {
        Args: { p_include_archived?: boolean; p_kind: string }
        Returns: Json
      }
      list_class_assignments: { Args: { p_class_id: string }; Returns: Json }
      list_class_students: {
        Args: { p_class_id: string; p_include_deleted?: boolean }
        Returns: Json
      }
      list_classes: {
        Args: {
          p_deleted?: boolean
          p_limit?: number
          p_offset?: number
          p_school_year?: string
          p_search?: string
        }
        Returns: Json
      }
      list_rooms: { Args: { p_include_archived?: boolean; p_site_id?: string }; Returns: Json }
      list_sites: { Args: { p_include_archived?: boolean }; Returns: Json }
      list_student_classes: { Args: { p_student_id: string }; Returns: Json }
      list_students: {
        Args: { p_limit?: number; p_offset?: number; p_search?: string; p_status?: string }
        Returns: Json
      }
      mark_avatar_verified: { Args: { p_path: string }; Returns: undefined }
      ops_prepare_account_create: {
        Args: { p_account_type: string; p_email: string; p_full_name: string; p_operator: string }
        Returns: {
          account_id: string
          command_id: string
        }[]
      }
      ops_prepare_temporary_password: {
        Args: { p_account_id: string; p_operator: string }
        Returns: string
      }
      ops_set_account: {
        Args: {
          p_account_id: string
          p_account_type?: string
          p_enabled?: boolean
          p_operator: string
        }
        Returns: Json
      }
      prepare_account_create: {
        Args: { p_birth_date?: string; p_email: string; p_full_name: string; p_phone?: string }
        Returns: {
          account_id: string
          command_id: string
        }[]
      }
      prepare_password_change: { Args: Record<PropertyKey, never>; Returns: string }
      prepare_password_reset: { Args: Record<PropertyKey, never>; Returns: string }
      prepare_temporary_password: {
        Args: { p_account_id: string; p_expected_version: number }
        Returns: string
      }
      preview_schedule_change: { Args: { p_change: Json; p_class_id: string }; Returns: Json }
      rename_catalog_entry: {
        Args: { p_expected_version: number; p_id: string; p_name: string }
        Returns: Json
      }
      reopen_class: { Args: { p_expected_version: number; p_id: string }; Returns: Json }
      reserve_avatar_upload: { Args: { p_extension: string }; Returns: string }
      restore_account: { Args: { p_account_id: string; p_expected_version: number }; Returns: Json }
      restore_catalog_entry: { Args: { p_expected_version: number; p_id: string }; Returns: Json }
      restore_class: { Args: { p_expected_version: number; p_id: string }; Returns: Json }
      restore_room: { Args: { p_expected_version: number; p_id: string }; Returns: Json }
      restore_site: { Args: { p_expected_version: number; p_id: string }; Returns: Json }
      restore_student: {
        Args: {
          p_birth_date: string
          p_expected_version: number
          p_full_name: string
          p_general_note: string
          p_id: string
          p_parent_name: string
          p_parent_phones: string[]
          p_school: string
          p_student_phones: string[]
        }
        Returns: Json
      }
      save_attendance: {
        Args: { p_fingerprint: string; p_session_id: string; p_students: Json }
        Returns: Json
      }
      set_account_enabled: {
        Args: { p_account_id: string; p_enabled: boolean; p_expected_version: number }
        Returns: Json
      }
      set_account_type: {
        Args: { p_account_id: string; p_account_type: string; p_expected_version: number }
        Returns: Json
      }
      set_my_avatar: { Args: { p_expected_version: number; p_path: string }; Returns: Json }
      set_participation_leave_date: {
        Args: { p_expected_version: number; p_id: string; p_leave_date: string }
        Returns: Json
      }
      set_participation_note: {
        Args: { p_expected_version: number; p_id: string; p_note: string }
        Returns: Json
      }
      soft_delete_account: {
        Args: { p_account_id: string; p_expected_version: number; p_reason: string }
        Returns: Json
      }
      soft_delete_class: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      soft_delete_class_student: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      soft_delete_student: {
        Args: { p_expected_version: number; p_id: string; p_reason: string }
        Returns: Json
      }
      student_delete_impact: { Args: { p_id: string }; Returns: Json }
      transfer_student: {
        Args: {
          p_expected_version: number
          p_join_date: string
          p_leave_date: string
          p_note: string
          p_participation_id: string
          p_target_class_id: string
        }
        Returns: Json
      }
      update_class:
        | {
            Args: {
              p_end_date: string
              p_expected_version: number
              p_grade_id: string
              p_id: string
              p_name: string
              p_note: string
              p_start_date: string
              p_subject_id: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_end_date: string
              p_expected_version: number
              p_grade_id: string
              p_id: string
              p_name: string
              p_note: string
              p_school_year_start: number
              p_start_date: string
              p_subject_id: string
            }
            Returns: Json
          }
      update_class_assignment: {
        Args: {
          p_end_date: string
          p_expected_version: number
          p_id: string
          p_role: string
          p_start_date: string
          p_subject_note: string
        }
        Returns: Json
      }
      update_my_profile: {
        Args: {
          p_birth_date: string
          p_expected_version: number
          p_full_name: string
          p_phone: string
        }
        Returns: Json
      }
      update_room: {
        Args: { p_expected_version: number; p_id: string; p_name: string; p_site_id: string }
        Returns: Json
      }
      update_site: {
        Args: { p_address: string; p_expected_version: number; p_id: string; p_name: string }
        Returns: Json
      }
      update_student: {
        Args: {
          p_birth_date: string
          p_expected_version: number
          p_full_name: string
          p_general_note: string
          p_id: string
          p_parent_name: string
          p_parent_phones: string[]
          p_school: string
          p_student_phones: string[]
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  api: {
    Enums: {},
  },
} as const
