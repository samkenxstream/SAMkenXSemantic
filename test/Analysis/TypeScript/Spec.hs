module Analysis.TypeScript.Spec (spec) where

import Control.Arrow ((&&&))
import Data.Abstract.Environment as Env
import Data.Abstract.Evaluatable
import Data.Abstract.Number as Number
import qualified Data.Abstract.ModuleTable as ModuleTable
import Data.Abstract.Value.Concrete as Value
import qualified Data.Language as Language
import qualified Data.List.NonEmpty as NonEmpty
import Data.Sum
import SpecHelpers

spec :: TaskConfig -> Spec
spec config = parallel $ do
  describe "TypeScript" $ do
    it "imports with aliased symbols" $ do
      (_, (_, res)) <- evaluate ["main.ts", "foo.ts", "a.ts", "foo/b.ts"]
      case ModuleTable.lookup "main.ts" <$> res of
        Right (Just (Module _ (env, _) :| [])) -> Env.names env `shouldBe` [ "bar", "quz" ]
        other -> expectationFailure (show other)

    it "imports with qualified names" $ do
      (_, (heap, res)) <- evaluate ["main1.ts", "foo.ts", "a.ts"]
      case ModuleTable.lookup "main1.ts" <$> res of
        Right (Just (Module _ (env, _) :| [])) -> do
          Env.names env `shouldBe` [ "b", "z" ]

          (derefQName heap ("b" :| []) env >>= deNamespace heap) `shouldBe` Just ("b", [ "baz", "foo" ])
          (derefQName heap ("z" :| []) env >>= deNamespace heap) `shouldBe` Just ("z", [ "baz", "foo" ])
        other -> expectationFailure (show other)

    it "side effect only imports" $ do
      (_, (_, res)) <- evaluate ["main2.ts", "a.ts", "foo.ts"]
      case ModuleTable.lookup "main2.ts" <$> res of
        Right (Just (Module _ (env, _) :| [])) -> env `shouldBe` lowerBound
        other -> expectationFailure (show other)

    it "fails exporting symbols not defined in the module" $ do
      (_, (_, res)) <- evaluate ["bad-export.ts", "pip.ts", "a.ts", "foo.ts"]
      res `shouldBe` Left (SomeExc (inject @(BaseError EvalError) (BaseError (ModuleInfo "foo.ts") emptySpan (ExportError "foo.ts" (name "pip")))))

    it "evaluates early return statements" $ do
      (_, (heap, res)) <- evaluate ["early-return.ts"]
      case ModuleTable.lookup "early-return.ts" <$> res of
        Right (Just (Module _ (_, addr) :| [])) -> heapLookupAll addr heap `shouldBe` Just [Value.Float (Number.Decimal 123.0)]
        other -> expectationFailure (show other)

    it "evaluates sequence expressions" $ do
      (_, (heap, res)) <- evaluate ["sequence-expression.ts"]
      case ModuleTable.lookup "sequence-expression.ts" <$> res of
        Right (Just (Module _ (env, addr) :| [])) -> do
          Env.names env `shouldBe` [ "x" ]
          (derefQName heap ("x" :| []) env) `shouldBe` Just (Value.Float (Number.Decimal 3.0))
        other -> expectationFailure (show other)

    it "evaluates void expressions" $ do
      (_, (heap, res)) <- evaluate ["void.ts"]
      case ModuleTable.lookup "void.ts" <$> res of
        Right (Just (Module _ (_, addr) :| [])) -> heapLookupAll addr heap `shouldBe` Just [Null]
        other -> expectationFailure (show other)

    it "evaluates delete" $ do
      (_, (heap, res)) <- evaluate ["delete.ts"]
      case ModuleTable.lookup "delete.ts" <$> res of
        Right (Just (Module _ (env, addr) :| [])) -> do
          heapLookupAll addr heap `shouldBe` Just [Unit]
          (derefQName heap ("x" :| []) env) `shouldBe` Nothing
          Env.names env `shouldBe` [ "x" ]
        other -> expectationFailure (show other)

    it "evaluates BOr statements" $ do
      (_, (heap, res)) <- evaluate ["bor.ts"]
      case ModuleTable.lookup "bor.ts" <$> res of
        Right (Just (Module _ (_, addr) :| [])) -> heapLookupAll addr heap `shouldBe` Just [Value.Integer (Number.Integer 3)]
        other -> expectationFailure (show other)

    it "evaluates BAnd statements" $ do
      (_, (heap, res)) <- evaluate ["band.ts"]
      case ModuleTable.lookup "band.ts" <$> res of
        Right (Just (Module _ (_, addr) :| [])) -> heapLookupAll addr heap `shouldBe` Just [Value.Integer (Number.Integer 0)]
        other -> expectationFailure (show other)

    it "evaluates BXOr statements" $ do
      (_, (heap, res)) <- evaluate ["bxor.ts"]
      case ModuleTable.lookup "bxor.ts" <$> res of
        Right (Just (Module _ (_, addr) :| [])) -> heapLookupAll addr heap `shouldBe` Just [Value.Integer (Number.Integer 3)]
        other -> expectationFailure (show other)

    it "evaluates LShift statements" $ do
      (_, (heap, res)) <- evaluate ["lshift.ts"]
      case ModuleTable.lookup "lshift.ts" <$> res of
        Right (Just (Module _ (_, addr) :| [])) -> heapLookupAll addr heap `shouldBe` Just [Value.Integer (Number.Integer 4)]
        other -> expectationFailure (show other)


  where
    fixtures = "test/fixtures/typescript/analysis/"
    evaluate = evalTypeScriptProject . map (fixtures <>)
    evalTypeScriptProject = testEvaluating <=< evaluateProject' config (Proxy :: Proxy 'Language.TypeScript) typescriptParser
