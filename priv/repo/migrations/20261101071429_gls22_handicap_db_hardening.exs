defmodule GolfScoring.Repo.Migrations.Gls22HandicapDbHardening do
  @moduledoc """
  Tightens handicap snapshot confirmation and built-state check constraints for GLS-22.
  """

  use Ecto.Migration

  def up do
    drop_if_exists(constraint(:handicap_snapshots, :handicap_snapshots_confirmer_shape))

    drop_if_exists(
      constraint(:handicap_snapshots, :handicap_snapshots_course_handicap_build_consistency)
    )

    create constraint(:handicap_snapshots, :handicap_snapshots_confirmer_shape,
             check: """
               (
               confirmed_at IS NULL
               AND confirmed_by_staff_user_id IS NULL
               AND confirmed_by_round_entry_id IS NULL
             )
             OR (
               confirmed_at IS NOT NULL
               AND (
                 (confirmed_by_staff_user_id IS NOT NULL)::int +
                 (confirmed_by_round_entry_id IS NOT NULL)::int
               ) = 1
             )
             """
           )

    create constraint(:handicap_snapshots, :handicap_snapshots_committee_deemed_provenance,
             check: """
               (basis_source <> 'committee_deemed')
             OR (source_reference IS NOT NULL AND btrim(source_reference) <> '')
             """
           )

    create constraint(:handicap_snapshots, :handicap_snapshots_course_handicap_build_consistency,
             check: """
               (
               built_at IS NULL
               AND course_rating IS NULL
               AND slope_rating IS NULL
               AND applicable_par IS NULL
               AND course_handicap_unrounded IS NULL
               AND course_handicap_rounded IS NULL
             )
             OR (
               built_at IS NOT NULL
               AND course_rating IS NOT NULL
               AND slope_rating IS NOT NULL
               AND applicable_par IS NOT NULL
               AND course_handicap_unrounded IS NOT NULL
               AND course_handicap_rounded IS NOT NULL
             )
             """
           )
  end

  def down do
    drop_if_exists(
      constraint(:handicap_snapshots, :handicap_snapshots_course_handicap_build_consistency)
    )

    drop_if_exists(
      constraint(:handicap_snapshots, :handicap_snapshots_committee_deemed_provenance)
    )

    drop_if_exists(constraint(:handicap_snapshots, :handicap_snapshots_confirmer_shape))

    create constraint(:handicap_snapshots, :handicap_snapshots_course_handicap_build_consistency,
             check: """
               (course_handicap_unrounded IS NULL
               AND course_handicap_rounded IS NULL
               AND built_at IS NULL)
             OR
             (course_handicap_unrounded IS NOT NULL
               AND course_handicap_rounded IS NOT NULL
               AND built_at IS NOT NULL)
             """
           )

    create constraint(:handicap_snapshots, :handicap_snapshots_confirmer_shape,
             check: """
               (confirmed_at IS NULL)
             OR (
               ((confirmed_by_staff_user_id IS NOT NULL)::int +
                (confirmed_by_round_entry_id IS NOT NULL)::int) = 1
             )
             """
           )
  end
end
