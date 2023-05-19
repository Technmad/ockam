#!/bin/bash

# ===== SETUP

setup_file() {
  load load/base.bash
}

setup() {
  load load/base.bash
  load load/orchestrator.bash
  load_bats_ext
  setup_home_dir
  skip_if_orchestrator_tests_not_enabled
  copy_local_orchestrator_data
}

teardown() {
  teardown_home_dir
}

# ===== TESTS

@test "projects - list" {
  run "$OCKAM" project list
  assert_success
}

@test "projects - enrollment" {
  ENROLLED_OCKAM_HOME=$OCKAM_HOME

  setup_home_dir
  NON_ENROLLED_OCKAM_HOME=$OCKAM_HOME

  run "$OCKAM" identity create green
  assert_success
  green_identifier=$($OCKAM identity show green)

  run "$OCKAM" identity create blue
  assert_success
  blue_identifier=$($OCKAM identity show blue)

  # They haven't been added by enroller yet
  run "$OCKAM" project enroll --identity green --project-path "$PROJECT_JSON_PATH"
  assert_failure

  OCKAM_HOME=$ENROLLED_OCKAM_HOME
  $OCKAM project ticket --member "$green_identifier" --attribute role=member
  blue_token=$($OCKAM project ticket --attribute role=member)
  OCKAM_HOME=$NON_ENROLLED_OCKAM_HOME

  # Green' identity was added by enroller
  run "$OCKAM" project enroll --identity green --project-path "$PROJECT_JSON_PATH"
  assert_success
  assert_output --partial "$green_identifier"

  # For blue, we use an enrollment token generated by enroller
  run "$OCKAM" project enroll $blue_token --identity blue
  assert_success
  assert_output --partial "$blue_identifier"
  OCKAM_HOME=$ENROLLED_OCKAM_HOME
}

@test "projects - access requiring credential" {
  ENROLLED_OCKAM_HOME=$OCKAM_HOME

  # Change to a new home directory where there are no enrolled identities
  setup_home_dir
  NON_ENROLLED_OCKAM_HOME=$OCKAM_HOME

  # Create a named default identity
  run "$OCKAM" identity create green
  green_identifier=$($OCKAM identity show green)

  # Create node for the non-enrolled identity using the exported project information
  run "$OCKAM" node create green --project-path "$ENROLLED_OCKAM_HOME/project.json"

  # Node can't create relay as it isn't a member
  fwd=$(random_str)
  run "$OCKAM" relay create "$fwd"
  assert_failure

  # Add node as a member
  OCKAM_HOME=$ENROLLED_OCKAM_HOME
  run "$OCKAM" project ticket --member "$green_identifier" --attribute role=member
  assert_success

  # The node can now access the project's services
  OCKAM_HOME=$NON_ENROLLED_OCKAM_HOME
  fwd=$(random_str)
  run "$OCKAM" relay create "$fwd"
  assert_success
}

@test "projects - send a message to a project node from an embedded node, enrolled member on different install" {
  skip # FIXME  how to send a message to a project m1 is enrolled to?  (with m1 being on a different install
  #       than the admin?.  If we pass project' address directly (instead of /project/ thing), would
  #       it present credential? would read authority info from project.json?

  $OCKAM project information --output json >/tmp/project.json

  export OCKAM_HOME=/tmp/ockam
  $OCKAM identity create m1
  $OCKAM identity create m2
  m1_identifier=$($OCKAM identity show m1)

  unset OCKAM_HOME
  $OCKAM project ticket --member $m1_identifier --attribute role=member

  export OCKAM_HOME=/tmp/ockam
  # m1' identity was added by enroller
  run $OCKAM project enroll --identity m1 --project-path "$PROJECT_JSON_PATH"

  # m1 is a member,  must be able to contact the project' service
  run $OCKAM message send --timeout 5 --identity m1 --project-path "$PROJECT_JSON_PATH" --to /project/default/service/echo hello
  assert_success
  assert_output "hello"

  # m2 is not a member,  must not be able to contact the project' service
  run $OCKAM message send --timeout 5 --identity m2 --project-path "$PROJECT_JSON_PATH" --to /project/default/service/echo hello
  assert_failure
}

@test "projects - list addons" {
  run "$OCKAM" project addon list --project default
  assert_success
  assert_output --partial "Id: okta"
}

@test "projects - enable and disable addons" {
  skip # TODO: wait until cloud has the influxdb and confluent addons enabled

  run "$OCKAM" project addon list --project default
  assert_success
  assert_output --partial --regex "Id: okta\n +Enabled: false"
  assert_output --partial --regex "Id: confluent\n +Enabled: false"

  run "$OCKAM" project addon enable okta --project default --tenant tenant --client-id client_id --cert cert
  assert_success
  run "$OCKAM" project addon enable confluent --project default --bootstrap-server bootstrap-server.confluent:9092 --api-key ApIkEy --api-secret ApIsEcrEt
  assert_success

  run "$OCKAM" project addon list --project default
  assert_success
  assert_output --partial --regex "Id: okta\n +Enabled: true"
  assert_output --partial --regex "Id: confluent\n +Enabled: true"

  run "$OCKAM" project addon disable --addon okta --project default
  run "$OCKAM" project addon disable --addon --project default
  run "$OCKAM" project addon disable --addon confluent --project default

  run "$OCKAM" project addon list --project default
  assert_success
  assert_output --partial --regex "Id: okta\n +Enabled: false"
  assert_output --partial --regex "Id: confluent\n +Enabled: false"
}

@test "influxdb lease manager" {
  # TODO add more tests
  #      responsible, and that a member enrolled on a different ockam install can access it.
  skip_if_influxdb_test_not_enabled

  run "$OCKAM" project addon configure influxdb --org-id "${INFLUXDB_ORG_ID}" --token "${INFLUXDB_TOKEN}" --endpoint-url "${INFLUXDB_ENDPOINT}" --max-ttl 60 --permissions "${INFLUXDB_PERMISSIONS}"
  assert_success

  sleep 30 #FIXME  workaround, project not yet ready after configuring addon

  $OCKAM project information default --output json >/tmp/project.json

  export OCKAM_HOME=/tmp/ockam
  run "$OCKAM" identity create m1
  run "$OCKAM" identity create m2
  run "$OCKAM" identity create m3

  m1_identifier=$($OCKAM identity show m1)
  m2_identifier=$($OCKAM identity show m2)

  unset OCKAM_HOME
  $OCKAM project ticket --member $m1_identifier --attribute service=sensor
  $OCKAM project ticket --member $m2_identifier --attribute service=web

  export OCKAM_HOME=/tmp/ockam

  # m1 and m2 identity was added by enroller
  run "$OCKAM" project enroll --identity m1 --project-path "$PROJECT_JSON_PATH"
  assert_success
  assert_output --partial $green_identifier

  run "$OCKAM" project enroll --identity m2 --project-path "$PROJECT_JSON_PATH"
  assert_success
  assert_output --partial $green_identifier

  # m1 and m2 can use the lease manager
  run "$OCKAM" lease --identity m1 --project-path "$PROJECT_JSON_PATH" create
  assert_success
  run "$OCKAM" lease --identity m2 --project-path "$PROJECT_JSON_PATH" create
  assert_success

  # m3 can't
  run "$OCKAM" lease --identity m3 --project-path "$PROJECT_JSON_PATH" create
  assert_failure

  unset OCKAM_HOME
  run "$OCKAM" project addon configure influxdb --org-id "${INFLUXDB_ORG_ID}" --token "${INFLUXDB_TOKEN}" --endpoint-url "${INFLUXDB_ENDPOINT}" --max-ttl 60 --permissions "${INFLUXDB_PERMISSIONS}" --user-access-role '(= subject.service "sensor")'
  assert_success

  sleep 30 #FIXME  workaround, project not yet ready after configuring addon

  export OCKAM_HOME=/tmp/ockam
  # m1 can use the lease manager (it has a service=sensor attribute attested by authority)
  run "$OCKAM" lease --identity m1 --project-path "$PROJECT_JSON_PATH" create
  assert_success

  # m2 can't use the  lease manager now (it doesn't have a service=sensor attribute attested by authority)
  run "$OCKAM" lease --identity m2 --project-path "$PROJECT_JSON_PATH" create
  assert_failure
}
