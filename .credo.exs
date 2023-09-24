%{
  configs: [
    %{
      name: "default",
      checks: %{
        disabled: [
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
