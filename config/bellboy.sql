CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE channels (
	id TEXT NOT NULL,
	name TEXT NOT NULL,
	channel_type TEXT NOT NULL,
	cid TEXT NOT NULL,
	created_by TEXT NOT NULL,
    image TEXT NOT NULL,
	description TEXT NOT NULL,
	public BOOLEAN NOT NULL,
	gate BOOLEAN NOT NULL,
	member_message_cooldown INT NULL,
	filter_words TEXT[] NULL,
	member_capabilities TEXT[] NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	truncated_at TIMESTAMPTZ NULL,
	parent_cid TEXT,
	topics_enabled BOOLEAN NOT NULL DEFAULT FALSE,
	is_closed_topic BOOLEAN NOT NULL DEFAULT FALSE,
	mls_enabled BOOLEAN NOT NULL DEFAULT FALSE,
	mls_enabled_at TIMESTAMPTZ NULL,
	e2ee_recovery_policy TEXT NOT NULL DEFAULT 'member_assisted'
		CHECK (e2ee_recovery_policy IN ('member_assisted', 'self_owned_only')),
	CONSTRAINT channels_cid_pk PRIMARY KEY (cid)
);

CREATE INDEX channel_project_id_prefix_index ON channels USING hash (left(id, 36));
CREATE INDEX channels_parent_cid_channel_type_index ON channels(parent_cid, channel_type);

CREATE TABLE members (
	user_id TEXT NOT NULL,
	cid TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	channel_role TEXT NOT NULL,
	last_read TIMESTAMPTZ NOT NULL,
	last_read_message_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
	last_send TIMESTAMPTZ NOT NULL,
	banned_at TIMESTAMPTZ NULL,
	blocked_at TIMESTAMPTZ NULL,
	muted TIMESTAMPTZ NULL,
    own_capabilities TEXT[] NULL,
	CONSTRAINT members_user_id_cid_pk PRIMARY KEY (user_id, cid)
);

CREATE INDEX members_user_id_index ON members(user_id);
CREATE INDEX members_cid_index ON members(cid);

CREATE TABLE channel_membership_events (
	event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	operation_id UUID NOT NULL,
	cid TEXT NOT NULL,
	user_id TEXT NOT NULL,
	event_kind TEXT NOT NULL CHECK (
		event_kind IN (
			'application_joined',
			'application_removed',
			'mls_included',
			'mls_excluded'
		)
	),
	occurred_at TIMESTAMPTZ NOT NULL,
	actor_user_id TEXT,
	source TEXT NOT NULL,
	caused_by_event_id UUID REFERENCES channel_membership_events(event_id),
	mls_epoch BIGINT CHECK (mls_epoch >= 0),
	removal_type TEXT,
	reason TEXT,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	CONSTRAINT channel_membership_events_kind_fields_check CHECK (
		(
			event_kind = 'application_joined'
			AND mls_epoch IS NULL
			AND removal_type IS NULL
			AND reason IS NULL
		)
		OR (
			event_kind = 'application_removed'
			AND mls_epoch IS NULL
			AND removal_type IN ('self_remove', 'kicked', 'invite_rejected', 'channel_deleted')
		)
		OR (
			event_kind IN ('mls_included', 'mls_excluded')
			AND mls_epoch IS NOT NULL
			AND removal_type IS NULL
			AND reason IS NULL
		)
	)
);

CREATE UNIQUE INDEX channel_membership_events_mls_transition_index
	ON channel_membership_events(cid, user_id, event_kind, mls_epoch)
	WHERE event_kind IN ('mls_included', 'mls_excluded');

CREATE INDEX channel_membership_events_removed_cursor_index
	ON channel_membership_events(user_id, occurred_at, event_id)
	WHERE event_kind = 'application_removed';

CREATE INDEX channel_membership_events_lifecycle_index
	ON channel_membership_events(cid, user_id, occurred_at, event_id);

CREATE TABLE member_removal_history (
	event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id TEXT NOT NULL,
	cid TEXT NOT NULL,
	removed_at TIMESTAMPTZ NOT NULL,
	removed_by TEXT NOT NULL,
	removal_type TEXT NOT NULL CHECK (removal_type IN ('self_remove', 'kicked', 'invite_rejected', 'channel_deleted')),
	reason TEXT NULL
);

CREATE INDEX member_removal_history_user_cursor_idx ON member_removal_history(user_id, removed_at, event_id);
CREATE INDEX member_removal_history_cid_idx ON member_removal_history(cid, removed_at);

CREATE TABLE devices (
	id TEXT NOT NULL,
	user_id TEXT NOT NULL,
	device_token TEXT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	CONSTRAINT devices_id_user_id_pk PRIMARY KEY (id, user_id)
);

CREATE INDEX devices_user_id_index ON devices(user_id);

CREATE TABLE client_sessions (
	device_id TEXT NOT NULL,
	user_id TEXT NOT NULL,
	last_seen_at TIMESTAMPTZ NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	CONSTRAINT client_sessions_pk PRIMARY KEY (device_id, user_id)
);

CREATE INDEX client_sessions_user_id_index ON client_sessions(user_id);

CREATE TABLE attachments (
    id UUID NOT NULL,
	attachment_type TEXT NULL,
    user_id TEXT NOT NULL,
	cid TEXT NOT NULL,
	url TEXT NOT NULL,
	thumb_url TEXT NOT NULL,
	file_name TEXT NOT NULL,
    content_type TEXT NOT NULL,
	content_length INT NOT NULL,
	content_disposition TEXT NOT NULL,
	message_id UUID NULL,
    created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL,
	deleted_at TIMESTAMPTZ,
	CONSTRAINT attachments_id_pk PRIMARY KEY (id)
);

CREATE INDEX attachments_cid_index ON attachments(cid);
CREATE INDEX attachments_cid_attachment_type_index ON attachments(cid, attachment_type);
CREATE INDEX attachments_deleted_at_index ON attachments (deleted_at) WHERE deleted_at IS NOT NULL;

CREATE TABLE contacts (
    user_id TEXT NOT NULL,
    other_id TEXT NOT NULL,
	project_id UUID NOT NULL,
    relation_status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT contacts_user_id_other_id_project_id_pk PRIMARY KEY (user_id, other_id, project_id)
);

CREATE INDEX contacts_user_id_index ON contacts(user_id);
CREATE INDEX contacts_other_id_index ON contacts(other_id);
CREATE INDEX contacts_user_id_project_id_index ON contacts(user_id, other_id);

CREATE TABLE pinned_messages (
	id UUID NOT NULL,
	cid TEXT NOT NULL,
	pinned_by TEXT NOT NULL,
    pinned_at TIMESTAMPTZ NOT NULL,
	CONSTRAINT pinned_messages_id_pk PRIMARY KEY (id)
);

CREATE INDEX pinned_messages_cid_index ON pinned_messages(cid);

CREATE TABLE pinned_channels (
	user_id TEXT NOT NULL,
	cid TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	CONSTRAINT pinned_channels_user_id_cid_pk PRIMARY KEY (user_id, cid)
);

CREATE INDEX pinned_channels_user_id_index ON pinned_channels(user_id);

CREATE TABLE key_packages (
    id UUID PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    key_package BYTEA NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    consumed BOOLEAN DEFAULT false,
    consumed_at TIMESTAMPTZ
);

CREATE INDEX key_packages_user_id_index ON key_packages(user_id);
CREATE INDEX key_packages_consumed_index ON key_packages(consumed);
CREATE INDEX key_packages_user_id_device_id_index ON key_packages(user_id, device_id);
CREATE INDEX key_packages_available_user_device_created_at_index ON key_packages(user_id, device_id, created_at, id) WHERE consumed = false;
CREATE INDEX key_packages_consumed_at_cleanup_index ON key_packages(consumed_at, id) WHERE consumed = true;

CREATE TABLE mls_epochs (
    cid TEXT PRIMARY KEY,
    epoch BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX mls_epochs_cid_index ON mls_epochs(cid);

CREATE TABLE mls_epoch_transitions (
    cid TEXT NOT NULL,
    epoch BIGINT NOT NULL CHECK (epoch >= 0),
    transitioned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (cid, epoch)
);

CREATE TABLE recovery_vaults (
    project_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    vault_bytes BYTEA NOT NULL,
    public_key BYTEA NOT NULL,
    key_id TEXT NOT NULL,
    ciphersuite SMALLINT NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    disabled_at TIMESTAMPTZ,
    PRIMARY KEY (project_id, user_id)
);

CREATE INDEX recovery_vaults_active_project_user_index ON recovery_vaults(project_id, user_id)
    WHERE is_active = TRUE;

CREATE TABLE mls_restore_authorization_intervals (
    cid TEXT NOT NULL,
    user_id TEXT NOT NULL,
    join_epoch BIGINT NOT NULL CHECK (join_epoch >= 0),
    leave_epoch BIGINT,
    opened_by_event_id UUID NOT NULL REFERENCES channel_membership_events(event_id),
    revoked_by_event_id UUID REFERENCES channel_membership_events(event_id),
    closed_by_event_id UUID REFERENCES channel_membership_events(event_id),
    PRIMARY KEY (cid, user_id, join_epoch),
    CONSTRAINT mls_restore_authorization_intervals_non_empty_check
        CHECK (leave_epoch IS NULL OR leave_epoch > join_epoch)
);

CREATE UNIQUE INDEX mls_restore_authorization_intervals_open_index
    ON mls_restore_authorization_intervals(cid, user_id)
    WHERE leave_epoch IS NULL;

CREATE INDEX mls_restore_authorization_intervals_restore_index
    ON mls_restore_authorization_intervals(cid, user_id, join_epoch, leave_epoch);

ALTER TABLE mls_restore_authorization_intervals
    ADD CONSTRAINT mls_restore_authorization_intervals_exclude_overlap
    EXCLUDE USING gist (
        cid WITH =,
        user_id WITH =,
        int8range(join_epoch, leave_epoch, '[)') WITH &&
    );

CREATE OR REPLACE FUNCTION channel_membership_events_member_insert_fn()
RETURNS trigger AS $$
BEGIN
    INSERT INTO channel_membership_events (
        operation_id,
        cid,
        user_id,
        event_kind,
        occurred_at,
        actor_user_id,
        source
    )
    VALUES (
        gen_random_uuid(),
        NEW.cid,
        NEW.user_id,
        'application_joined',
        NEW.created_at,
        NULL,
        'members_insert_trigger'
    );

    UPDATE mls_restore_authorization_intervals
    SET revoked_by_event_id = NULL
    WHERE cid = NEW.cid
      AND user_id = NEW.user_id
      AND leave_epoch IS NULL;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER channel_membership_events_member_insert_trigger
AFTER INSERT ON members
FOR EACH ROW EXECUTE FUNCTION channel_membership_events_member_insert_fn();

CREATE OR REPLACE FUNCTION channel_membership_events_member_removed_fn()
RETURNS trigger AS $$
BEGIN
    INSERT INTO channel_membership_events (
        event_id,
        operation_id,
        cid,
        user_id,
        event_kind,
        occurred_at,
        actor_user_id,
        source,
        removal_type,
        reason
    )
    VALUES (
        NEW.event_id,
        NEW.event_id,
        NEW.cid,
        NEW.user_id,
        'application_removed',
        NEW.removed_at,
        NEW.removed_by,
        'member_removal_history_trigger',
        NEW.removal_type,
        NEW.reason
    )
    ON CONFLICT (event_id) DO NOTHING;

    UPDATE mls_restore_authorization_intervals
    SET revoked_by_event_id = NEW.event_id
    WHERE cid = NEW.cid
      AND user_id = NEW.user_id
      AND leave_epoch IS NULL;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER channel_membership_events_member_removed_trigger
AFTER INSERT ON member_removal_history
FOR EACH ROW EXECUTE FUNCTION channel_membership_events_member_removed_fn();

CREATE TABLE mls_transition_operations (
    operation_id UUID PRIMARY KEY,
    cid TEXT NOT NULL,
    expected_epoch BIGINT NOT NULL CHECK (expected_epoch >= 0),
    new_epoch BIGINT NOT NULL CHECK (new_epoch = expected_epoch + 1),
    request_hash TEXT NOT NULL,
    status TEXT NOT NULL CHECK (
        status IN ('pending', 'delivering', 'retry_wait', 'delivered', 'blocked')
    ),
    attempt_count SMALLINT NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    UNIQUE (cid, new_epoch),
    UNIQUE (cid, request_hash)
);

CREATE INDEX mls_transition_operations_delivery_index
    ON mls_transition_operations(next_attempt_at, created_at)
    WHERE status IN ('pending', 'retry_wait', 'delivering');

CREATE INDEX mls_transition_operations_cid_status_index
    ON mls_transition_operations(cid, status, new_epoch);

CREATE TABLE mls_transition_outbox_items (
    operation_id UUID NOT NULL REFERENCES mls_transition_operations(operation_id) ON DELETE CASCADE,
    sequence SMALLINT NOT NULL CHECK (sequence >= 0),
    item_kind TEXT NOT NULL CHECK (item_kind IN ('protocol_event', 'group_info')),
    event_id UUID,
    epoch BIGINT NOT NULL CHECK (epoch >= 0),
    occurred_at TIMESTAMPTZ NOT NULL,
    payload BYTEA NOT NULL CHECK (octet_length(payload) <= 1048576),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'delivered')),
    delivered_at TIMESTAMPTZ,
    last_error TEXT,
    PRIMARY KEY (operation_id, sequence),
    CONSTRAINT mls_transition_outbox_items_event_id_check CHECK (
        (item_kind = 'protocol_event' AND event_id IS NOT NULL)
        OR (item_kind = 'group_info' AND event_id IS NULL)
    )
);

CREATE UNIQUE INDEX mls_transition_outbox_protocol_event_index
    ON mls_transition_outbox_items(event_id)
    WHERE event_id IS NOT NULL;

CREATE TABLE mls_archive_manifests (
    cid TEXT NOT NULL,
    epoch BIGINT NOT NULL CHECK (epoch >= 0),
    archive_blob_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    scope TEXT NOT NULL CHECK (scope IN ('account_owned', 'group_sponsored')),
    coverage_key TEXT NOT NULL,
    exporter_user_id TEXT NOT NULL,
    recipient_set_hash TEXT,
    candidate_slot SMALLINT NOT NULL CHECK (candidate_slot BETWEEN 0 AND 1),
    request_hash TEXT NOT NULL,
    snapshot_hash TEXT NOT NULL,
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ,
    compatibility_indexed_at TIMESTAMPTZ,
    status TEXT NOT NULL CHECK (status IN ('pending', 'complete', 'failed', 'expired')),
    cleanup_status TEXT NOT NULL DEFAULT 'not_required'
        CHECK (cleanup_status IN ('not_required', 'pending', 'material_cleaned', 'cleaned', 'blocked')),
    reconcile_attempts SMALLINT NOT NULL DEFAULT 0 CHECK (reconcile_attempts >= 0),
    last_error TEXT,
    cleanup_error TEXT,
    material_deleted_at TIMESTAMPTZ,
    snapshot_deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    PRIMARY KEY (cid, archive_blob_id),
    UNIQUE (cid, idempotency_key)
);

CREATE UNIQUE INDEX mls_archive_manifests_account_candidate_slot_index
    ON mls_archive_manifests(cid, epoch, coverage_key, candidate_slot)
    WHERE scope = 'account_owned' AND status IN ('pending', 'complete');

CREATE UNIQUE INDEX mls_archive_manifests_sponsored_candidate_slot_index
    ON mls_archive_manifests(cid, epoch, candidate_slot)
    WHERE scope = 'group_sponsored' AND status IN ('pending', 'complete');

CREATE UNIQUE INDEX mls_archive_manifests_sponsored_exporter_index
    ON mls_archive_manifests(cid, epoch, exporter_user_id)
    WHERE scope = 'group_sponsored' AND status IN ('pending', 'complete');

CREATE INDEX mls_archive_manifests_complete_query_index
    ON mls_archive_manifests(cid, epoch, status);

CREATE INDEX mls_archive_manifests_reconcile_index
    ON mls_archive_manifests(status, updated_at)
    WHERE status IN ('pending', 'failed');

CREATE INDEX mls_archive_manifests_compatibility_index
    ON mls_archive_manifests(completed_at)
    WHERE status = 'complete' AND compatibility_indexed_at IS NULL;

CREATE INDEX mls_archive_manifests_cleanup_index
    ON mls_archive_manifests(updated_at)
    WHERE status = 'expired' AND cleanup_status IN ('pending', 'material_cleaned', 'blocked');

CREATE TABLE mls_archive_recipients (
    cid TEXT NOT NULL,
    archive_blob_id TEXT NOT NULL,
    epoch BIGINT NOT NULL CHECK (epoch >= 0),
    recipient_user_id TEXT NOT NULL,
    recipient_recovery_key_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (cid, archive_blob_id, recipient_user_id, recipient_recovery_key_id),
    FOREIGN KEY (cid, archive_blob_id)
        REFERENCES mls_archive_manifests(cid, archive_blob_id)
        ON DELETE CASCADE
);

CREATE INDEX mls_archive_recipients_availability_index
    ON mls_archive_recipients(cid, recipient_user_id, epoch, archive_blob_id);

TRUNCATE channels, members, channel_membership_events, member_removal_history, devices, client_sessions, attachments, contacts, pinned_messages, pinned_channels, key_packages, mls_epochs, mls_epoch_transitions, recovery_vaults, mls_restore_authorization_intervals, mls_transition_outbox_items, mls_transition_operations, mls_archive_recipients, mls_archive_manifests RESTART IDENTITY;
