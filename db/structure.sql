SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: account_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.account_kind AS ENUM (
    'asset',
    'liability',
    'equity',
    'income',
    'expense',
    'suspense'
);


--
-- Name: ledger_assert_entry_balanced(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_assert_entry_balanced() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  entry_ids bigint[] := ARRAY[]::bigint[];
  eid bigint;
  posting_count integer;
  total numeric;
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    entry_ids := array_append(entry_ids, NEW.journal_entry_id);
  END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    entry_ids := array_append(entry_ids, OLD.journal_entry_id);
  END IF;

  FOREACH eid IN ARRAY entry_ids LOOP
    SELECT count(*), coalesce(sum(amount_paise), 0)
      INTO posting_count, total
      FROM postings WHERE journal_entry_id = eid;

    IF posting_count = 0 THEN
      -- Fine if the entry itself is gone (e.g. household deletion cascade).
      IF EXISTS (SELECT 1 FROM journal_entries WHERE id = eid) THEN
        RAISE EXCEPTION 'journal entry % has no postings', eid
          USING ERRCODE = 'check_violation', CONSTRAINT = 'journal_entry_has_postings';
      END IF;
    ELSIF total <> 0 THEN
      RAISE EXCEPTION 'journal entry % is unbalanced: postings sum to % paise', eid, total
        USING ERRCODE = 'check_violation', CONSTRAINT = 'journal_entry_balanced';
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;


--
-- Name: ledger_assert_entry_has_postings(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_assert_entry_has_postings() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM journal_entries WHERE id = NEW.id)
     AND NOT EXISTS (SELECT 1 FROM postings WHERE journal_entry_id = NEW.id) THEN
    RAISE EXCEPTION 'journal entry % has no postings', NEW.id
      USING ERRCODE = 'check_violation', CONSTRAINT = 'journal_entry_has_postings';
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: ledger_forbid_posting_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_forbid_posting_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'postings are append-only; post a reversing entry instead'
    USING ERRCODE = 'restrict_violation';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    household_id bigint NOT NULL,
    name character varying NOT NULL,
    kind public.account_kind NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: households; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.households (
    id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: households_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.households_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: households_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.households_id_seq OWNED BY public.households.id;


--
-- Name: journal_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_entries (
    id bigint NOT NULL,
    household_id bigint NOT NULL,
    occurred_on date NOT NULL,
    memo character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: journal_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.journal_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: journal_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.journal_entries_id_seq OWNED BY public.journal_entries.id;


--
-- Name: postings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.postings (
    id bigint NOT NULL,
    household_id bigint NOT NULL,
    journal_entry_id bigint NOT NULL,
    account_id bigint NOT NULL,
    amount_paise bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT postings_amount_nonzero CHECK ((amount_paise <> 0))
);


--
-- Name: postings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.postings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: postings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.postings_id_seq OWNED BY public.postings.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    household_id bigint NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: households id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.households ALTER COLUMN id SET DEFAULT nextval('public.households_id_seq'::regclass);


--
-- Name: journal_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries ALTER COLUMN id SET DEFAULT nextval('public.journal_entries_id_seq'::regclass);


--
-- Name: postings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postings ALTER COLUMN id SET DEFAULT nextval('public.postings_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: households households_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.households
    ADD CONSTRAINT households_pkey PRIMARY KEY (id);


--
-- Name: journal_entries journal_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);


--
-- Name: postings postings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postings
    ADD CONSTRAINT postings_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_accounts_on_household_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounts_on_household_id ON public.accounts USING btree (household_id);


--
-- Name: index_accounts_on_household_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_household_id_and_name ON public.accounts USING btree (household_id, name);


--
-- Name: index_accounts_on_id_and_household_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_id_and_household_id ON public.accounts USING btree (id, household_id);


--
-- Name: index_accounts_one_suspense_per_household; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_one_suspense_per_household ON public.accounts USING btree (household_id) WHERE (kind = 'suspense'::public.account_kind);


--
-- Name: index_journal_entries_on_household_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_household_id ON public.journal_entries USING btree (household_id);


--
-- Name: index_journal_entries_on_household_id_and_occurred_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_household_id_and_occurred_on ON public.journal_entries USING btree (household_id, occurred_on);


--
-- Name: index_journal_entries_on_id_and_household_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_journal_entries_on_id_and_household_id ON public.journal_entries USING btree (id, household_id);


--
-- Name: index_postings_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_postings_on_account_id ON public.postings USING btree (account_id);


--
-- Name: index_postings_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_postings_on_journal_entry_id ON public.postings USING btree (journal_entry_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: index_users_on_household_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_household_id ON public.users USING btree (household_id);


--
-- Name: journal_entries journal_entries_have_postings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER journal_entries_have_postings AFTER INSERT ON public.journal_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ledger_assert_entry_has_postings();


--
-- Name: postings postings_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER postings_append_only BEFORE UPDATE ON public.postings FOR EACH ROW EXECUTE FUNCTION public.ledger_forbid_posting_update();


--
-- Name: postings postings_balanced; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER postings_balanced AFTER INSERT OR DELETE OR UPDATE ON public.postings DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ledger_assert_entry_balanced();


--
-- Name: postings fk_postings_account_same_household; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postings
    ADD CONSTRAINT fk_postings_account_same_household FOREIGN KEY (account_id, household_id) REFERENCES public.accounts(id, household_id);


--
-- Name: postings fk_postings_entry_same_household; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postings
    ADD CONSTRAINT fk_postings_entry_same_household FOREIGN KEY (journal_entry_id, household_id) REFERENCES public.journal_entries(id, household_id) ON DELETE CASCADE;


--
-- Name: postings fk_postings_household; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postings
    ADD CONSTRAINT fk_postings_household FOREIGN KEY (household_id) REFERENCES public.households(id) ON DELETE CASCADE;


--
-- Name: accounts fk_rails_232fbe7131; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_rails_232fbe7131 FOREIGN KEY (household_id) REFERENCES public.households(id) ON DELETE CASCADE;


--
-- Name: journal_entries fk_rails_432547a4f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_432547a4f9 FOREIGN KEY (household_id) REFERENCES public.households(id) ON DELETE CASCADE;


--
-- Name: users fk_rails_5121351c36; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_5121351c36 FOREIGN KEY (household_id) REFERENCES public.households(id) ON DELETE CASCADE;


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261119120000'),
('20261119115125'),
('20261119115124');

