%{
  configs: [
    %{
      name: "default",
      checks: %{
        disabled: [
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
