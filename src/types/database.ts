export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      audit_logs: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string | null
          id: string
          metadata: Json
          reason: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          reason?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          reason?: string | null
        }
        Relationships: []
      }
      business_members: {
        Row: {
          business_id: string
          created_at: string
          member_role: Database["public"]["Enums"]["member_role"]
          user_id: string
        }
        Insert: {
          business_id: string
          created_at?: string
          member_role?: Database["public"]["Enums"]["member_role"]
          user_id: string
        }
        Update: {
          business_id?: string
          created_at?: string
          member_role?: Database["public"]["Enums"]["member_role"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "business_members_business_id_fkey"
            columns: ["business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "business_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      businesses: {
        Row: {
          address_text: string | null
          business_type: Database["public"]["Enums"]["business_type"]
          city_id: string | null
          commercial_registration_no: string | null
          created_at: string
          created_by: string | null
          description_ar: string | null
          email: string | null
          governorate_id: string
          id: string
          is_active: boolean
          legal_name: string | null
          logo_path: string | null
          name_ar: string
          name_en: string | null
          phone: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          tax_id: string | null
          updated_at: string
          verification_reason: string | null
          verification_status: Database["public"]["Enums"]["verification_status"]
        }
        Insert: {
          address_text?: string | null
          business_type: Database["public"]["Enums"]["business_type"]
          city_id?: string | null
          commercial_registration_no?: string | null
          created_at?: string
          created_by?: string | null
          description_ar?: string | null
          email?: string | null
          governorate_id: string
          id?: string
          is_active?: boolean
          legal_name?: string | null
          logo_path?: string | null
          name_ar: string
          name_en?: string | null
          phone?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          tax_id?: string | null
          updated_at?: string
          verification_reason?: string | null
          verification_status?: Database["public"]["Enums"]["verification_status"]
        }
        Update: {
          address_text?: string | null
          business_type?: Database["public"]["Enums"]["business_type"]
          city_id?: string | null
          commercial_registration_no?: string | null
          created_at?: string
          created_by?: string | null
          description_ar?: string | null
          email?: string | null
          governorate_id?: string
          id?: string
          is_active?: boolean
          legal_name?: string | null
          logo_path?: string | null
          name_ar?: string
          name_en?: string | null
          phone?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          tax_id?: string | null
          updated_at?: string
          verification_reason?: string | null
          verification_status?: Database["public"]["Enums"]["verification_status"]
        }
        Relationships: [
          {
            foreignKeyName: "businesses_city_id_fkey"
            columns: ["city_id"]
            isOneToOne: false
            referencedRelation: "cities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "businesses_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "businesses_governorate_id_fkey"
            columns: ["governorate_id"]
            isOneToOne: false
            referencedRelation: "governorates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "businesses_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      checkout_sessions: {
        Row: {
          id: string
          buyer_user_id: string
          buyer_business_id: string | null
          delivery_address: string
          status: string
          total_amount: number
          currency: string
          expires_at: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          buyer_user_id: string
          buyer_business_id?: string | null
          delivery_address: string
          status?: string
          total_amount?: number
          currency?: string
          expires_at?: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          status?: string
          total_amount?: number
          updated_at?: string
        }
        Relationships: []
      }
      categories: {
        Row: {
          created_at: string
          description_ar: string | null
          icon: string | null
          id: string
          image_path: string | null
          is_active: boolean
          name_ar: string
          name_en: string | null
          parent_id: string | null
          slug: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          description_ar?: string | null
          icon?: string | null
          id?: string
          image_path?: string | null
          is_active?: boolean
          name_ar: string
          name_en?: string | null
          parent_id?: string | null
          slug: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          description_ar?: string | null
          icon?: string | null
          id?: string
          image_path?: string | null
          is_active?: boolean
          name_ar?: string
          name_en?: string | null
          parent_id?: string | null
          slug?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "categories_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
        ]
      }
      cities: {
        Row: {
          created_at: string
          governorate_id: string
          id: string
          is_active: boolean
          name_ar: string
          name_en: string | null
          sort_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          governorate_id: string
          id?: string
          is_active?: boolean
          name_ar: string
          name_en?: string | null
          sort_order?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          governorate_id?: string
          id?: string
          is_active?: boolean
          name_ar?: string
          name_en?: string | null
          sort_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cities_governorate_id_fkey"
            columns: ["governorate_id"]
            isOneToOne: false
            referencedRelation: "governorates"
            referencedColumns: ["id"]
          },
        ]
      }
      governorates: {
        Row: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          name_ar: string
          name_en: string | null
          sort_order: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          name_ar: string
          name_en?: string | null
          sort_order?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          name_ar?: string
          name_en?: string | null
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      order_items: {
        Row: {
          created_at: string
          id: string
          line_total: number | null
          order_id: string
          product_id: string
          product_name: string
          quantity: number
          unit_price: number
        }
        Insert: {
          created_at?: string
          id?: string
          line_total?: number | null
          order_id: string
          product_id: string
          product_name: string
          quantity: number
          unit_price: number
        }
        Update: {
          created_at?: string
          id?: string
          line_total?: number | null
          order_id?: string
          product_id?: string
          product_name?: string
          quantity?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "order_items_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      orders: {
        Row: {
          buyer_business_id: string | null
          buyer_user_id: string | null
          order_type: string
          checkout_session_id: string | null
          created_at: string
          currency: string
          delivery_address: string | null
          id: string
          notes: string | null
          rfq_id: string | null
          status: string
          supplier_business_id: string
          total_amount: number
          updated_at: string
        }
        Insert: {
          buyer_business_id?: string | null
          buyer_user_id?: string | null
          order_type?: string
          checkout_session_id?: string | null
          created_at?: string
          currency?: string
          delivery_address?: string | null
          id?: string
          notes?: string | null
          rfq_id?: string | null
          status?: string
          supplier_business_id: string
          total_amount?: number
          updated_at?: string
        }
        Update: {
          buyer_business_id?: string | null
          buyer_user_id?: string | null
          order_type?: string
          checkout_session_id?: string | null
          created_at?: string
          currency?: string
          delivery_address?: string | null
          id?: string
          notes?: string | null
          rfq_id?: string | null
          status?: string
          supplier_business_id?: string
          total_amount?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "orders_buyer_business_id_fkey"
            columns: ["buyer_business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_rfq_id_fkey"
            columns: ["rfq_id"]
            isOneToOne: false
            referencedRelation: "rfqs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_supplier_business_id_fkey"
            columns: ["supplier_business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_reservations: {
        Row: { id: string; order_id: string; product_id: string; supplier_business_id: string; quantity: number; status: string; expires_at: string; created_at: string; resolved_at: string | null }
        Insert: { id?: string; order_id: string; product_id: string; supplier_business_id: string; quantity: number; status?: string; expires_at: string; created_at?: string; resolved_at?: string | null }
        Update: { id?: string; order_id?: string; product_id?: string; supplier_business_id?: string; quantity?: number; status?: string; expires_at?: string; created_at?: string; resolved_at?: string | null }
        Relationships: []
      }
      escrow_ledger_entries: {
        Row: { id: string; order_id: string; entry_type: string; amount: number; currency: string; provider_reference: string | null; idempotency_key: string; metadata: Json; actor_id: string | null; created_at: string }
        Insert: { id?: string; order_id: string; entry_type: string; amount: number; currency?: string; provider_reference?: string | null; idempotency_key: string; metadata?: Json; actor_id?: string | null; created_at?: string }
        Update: { id?: string; order_id?: string; entry_type?: string; amount?: number; currency?: string; provider_reference?: string | null; idempotency_key?: string; metadata?: Json; actor_id?: string | null; created_at?: string }
        Relationships: []
      }
      permissions: {
        Row: {
          group_key: string
          key: string
          name_ar: string
        }
        Insert: {
          group_key: string
          key: string
          name_ar: string
        }
        Update: {
          group_key?: string
          key?: string
          name_ar?: string
        }
        Relationships: []
      }
      product_sample_requests: {
        Row: { id: string; product_id: string; buyer_business_id: string; supplier_business_id: string; requested_by: string; quantity: number; unit_price: number; total_amount: number; status: string; delivery_address: string; created_at: string; updated_at: string }
        Insert: { id?: string; product_id: string; buyer_business_id: string; supplier_business_id: string; requested_by: string; quantity: number; unit_price: number; status?: string; delivery_address: string; created_at?: string; updated_at?: string }
        Update: { status?: string; updated_at?: string }
        Relationships: []
      }
      proforma_invoices: {
        Row: { id: string; invoice_number: string; order_id: string; supplier_business_id: string; buyer_business_id: string; currency: string; subtotal: number; terms: string | null; issued_at: string; valid_until: string | null; status: string; created_by: string; created_at: string }
        Insert: { id?: string; invoice_number: string; order_id: string; supplier_business_id: string; buyer_business_id: string; currency?: string; subtotal: number; terms?: string | null; issued_at?: string; valid_until?: string | null; status?: string; created_by: string; created_at?: string }
        Update: { status?: string; valid_until?: string | null; terms?: string | null }
        Relationships: []
      }
      proforma_invoice_items: {
        Row: { id: string; proforma_invoice_id: string; product_id: string; product_name: string; quantity: number; unit_price: number; line_total: number }
        Insert: { id?: string; proforma_invoice_id: string; product_id: string; product_name: string; quantity: number; unit_price: number }
        Update: never
        Relationships: []
      }
      product_price_tiers: {
        Row: {
          created_at: string
          id: string
          min_quantity: number
          product_id: string
          unit_price: number
        }
        Insert: {
          created_at?: string
          id?: string
          min_quantity: number
          product_id: string
          unit_price: number
        }
        Update: {
          created_at?: string
          id?: string
          min_quantity?: number
          product_id?: string
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "product_price_tiers_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          business_id: string
          category_id: string | null
          created_at: string
          description: string | null
          id: string
          image_path: string | null
          is_active: boolean
          min_order_quantity: number
          name: string
          price: number
          retail_price: number | null
          is_retail_available: boolean
          sample_available: boolean
          sample_price: number | null
          sample_max_quantity: number
          sku: string | null
          stock_quantity: number
          reserved_quantity: number
          available_quantity: number
          updated_at: string
        }
        Insert: {
          business_id: string
          category_id?: string | null
          created_at?: string
          description?: string | null
          id?: string
          image_path?: string | null
          is_active?: boolean
          min_order_quantity?: number
          name: string
          price?: number
          retail_price?: number | null
          is_retail_available?: boolean
          sample_available?: boolean
          sample_price?: number | null
          sample_max_quantity?: number
          sku?: string | null
          stock_quantity?: number
          updated_at?: string
        }
        Update: {
          business_id?: string
          category_id?: string | null
          created_at?: string
          description?: string | null
          id?: string
          image_path?: string | null
          is_active?: boolean
          min_order_quantity?: number
          name?: string
          price?: number
          retail_price?: number | null
          is_retail_available?: boolean
          sample_available?: boolean
          sample_price?: number | null
          sample_max_quantity?: number
          sku?: string | null
          stock_quantity?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "products_business_id_fkey"
            columns: ["business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          full_name: string | null
          id: string
          phone: string | null
          status: Database["public"]["Enums"]["account_status"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          full_name?: string | null
          id: string
          phone?: string | null
          status?: Database["public"]["Enums"]["account_status"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          full_name?: string | null
          id?: string
          phone?: string | null
          status?: Database["public"]["Enums"]["account_status"]
          updated_at?: string
        }
        Relationships: []
      }
      rfq_items: {
        Row: {
          created_at: string
          id: string
          product_id: string
          quantity: number
          rfq_id: string
          supplier_business_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          product_id: string
          quantity: number
          rfq_id: string
          supplier_business_id: string
        }
        Update: {
          created_at?: string
          id?: string
          product_id?: string
          quantity?: number
          rfq_id?: string
          supplier_business_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rfq_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rfq_items_rfq_id_fkey"
            columns: ["rfq_id"]
            isOneToOne: false
            referencedRelation: "rfqs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rfq_items_supplier_business_id_fkey"
            columns: ["supplier_business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
        ]
      }
      rfq_offers: {
        Row: {
          created_at: string
          currency: string
          delivery_days: number | null
          id: string
          notes: string | null
          quantity: number
          rfq_id: string
          status: string
          supplier_business_id: string
          total_price: number | null
          unit_price: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          currency?: string
          delivery_days?: number | null
          id?: string
          notes?: string | null
          quantity: number
          rfq_id: string
          status?: string
          supplier_business_id: string
          total_price?: number | null
          unit_price: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          currency?: string
          delivery_days?: number | null
          id?: string
          notes?: string | null
          quantity?: number
          rfq_id?: string
          status?: string
          supplier_business_id?: string
          total_price?: number | null
          unit_price?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rfq_offers_rfq_id_fkey"
            columns: ["rfq_id"]
            isOneToOne: false
            referencedRelation: "rfqs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rfq_offers_supplier_business_id_fkey"
            columns: ["supplier_business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
        ]
      }
      rfqs: {
        Row: {
          awarded_offer_id: string | null
          buyer_business_id: string
          created_at: string
          deadline: string | null
          delivery_city_id: string | null
          delivery_governorate_id: string | null
          description: string | null
          id: string
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          awarded_offer_id?: string | null
          buyer_business_id: string
          created_at?: string
          deadline?: string | null
          delivery_city_id?: string | null
          delivery_governorate_id?: string | null
          description?: string | null
          id?: string
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          awarded_offer_id?: string | null
          buyer_business_id?: string
          created_at?: string
          deadline?: string | null
          delivery_city_id?: string | null
          delivery_governorate_id?: string | null
          description?: string | null
          id?: string
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rfqs_buyer_business_id_fkey"
            columns: ["buyer_business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rfqs_delivery_city_id_fkey"
            columns: ["delivery_city_id"]
            isOneToOne: false
            referencedRelation: "cities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rfqs_delivery_governorate_id_fkey"
            columns: ["delivery_governorate_id"]
            isOneToOne: false
            referencedRelation: "governorates"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          permission_key: string
          role_id: string
        }
        Insert: {
          permission_key: string
          role_id: string
        }
        Update: {
          permission_key?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          created_at: string
          description_ar: string | null
          id: string
          is_system: boolean
          key: string
          name_ar: string
        }
        Insert: {
          created_at?: string
          description_ar?: string | null
          id?: string
          is_system?: boolean
          key: string
          name_ar: string
        }
        Update: {
          created_at?: string
          description_ar?: string | null
          id?: string
          is_system?: boolean
          key?: string
          name_ar?: string
        }
        Relationships: []
      }
      staff_roles: {
        Row: {
          created_at: string
          granted_by: string | null
          role_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          granted_by?: string | null
          role_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          granted_by?: string | null
          role_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_roles_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      append_escrow_ledger_entry: { Args: { p_order_id: string; p_entry_type: string; p_amount: number; p_idempotency_key: string; p_provider_reference?: string | null; p_metadata?: Json }; Returns: string }
      confirm_inventory_reservation: { Args: { p_order_id: string }; Returns: number }
      release_expired_inventory_reservations: { Args: { p_limit?: number }; Returns: number }
      create_hybrid_checkout: {
        Args: {
          p_buyer_business_id: string | null
          p_retail_items: Json
          p_wholesale_items: Json
          p_delivery_address: string
        }
        Returns: Json
      }
      create_retail_orders: { Args: { p_items: Json; p_delivery_address: string }; Returns: Json }
      create_wholesale_orders: { Args: { p_buyer_business_id: string; p_items: Json; p_delivery_address: string }; Returns: Json }
      create_product_sample_request: { Args: { p_buyer_business_id: string; p_product_id: string; p_quantity: number; p_delivery_address: string }; Returns: string }
      create_proforma_invoice: { Args: { p_order_id: string; p_valid_until?: string | null; p_terms?: string | null }; Returns: string }
      accept_rfq_offer: { Args: { p_offer_id: string }; Returns: undefined }
      create_business: {
        Args: {
          p_business_type: Database["public"]["Enums"]["business_type"]
          p_city_id?: string
          p_governorate_id: string
          p_name_ar: string
          p_phone?: string
        }
        Returns: string
      }
      create_rfq_for_product: {
        Args: {
          p_buyer_business_id: string
          p_notes?: string
          p_product_id: string
          p_quantity: number
        }
        Returns: string
      }
      get_public_supplier_names: {
        Args: { p_business_ids?: string[] }
        Returns: {
          id: string
          name_ar: string
        }[]
      }
      has_business_role: {
        Args: {
          p_business_id: string
          p_roles: Database["public"]["Enums"]["member_role"][]
        }
        Returns: boolean
      }
      has_permission: { Args: { p_key: string }; Returns: boolean }
      is_business_member: { Args: { p_business_id: string }; Returns: boolean }
      my_permissions: { Args: never; Returns: string[] }
      submit_rfq_offer: {
        Args: {
          p_delivery_days: number
          p_notes?: string
          p_rfq_id: string
          p_supplier_business_id: string
          p_total_price: number
        }
        Returns: string
      }
      write_audit_log: {
        Args: {
          p_action: string
          p_entity_id: string
          p_entity_type: string
          p_metadata?: Json
          p_reason?: string
        }
        Returns: undefined
      }
    }
    Enums: {
      account_status: "active" | "suspended"
      business_type: "buyer" | "supplier"
      member_role: "owner" | "manager" | "staff"
      verification_status:
        | "draft"
        | "submitted"
        | "under_review"
        | "approved"
        | "rejected"
        | "suspended"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      account_status: ["active", "suspended"],
      business_type: ["buyer", "supplier"],
      member_role: ["owner", "manager", "staff"],
      verification_status: [
        "draft",
        "submitted",
        "under_review",
        "approved",
        "rejected",
        "suspended",
      ],
    },
  },
} as const
