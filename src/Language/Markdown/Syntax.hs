{-# LANGUAGE DataKinds, DeriveAnyClass, GADTs, RankNTypes, TypeOperators #-}
module Language.Markdown.Syntax
( assignment
, Syntax
, Grammar.Grammar
, Error
, Term
) where

import qualified CMark
import Data.Functor.Union
import Data.Record
import Data.Syntax.Assignment hiding (Assignment, Error)
import qualified Data.Syntax.Assignment as Assignment
import qualified Data.Syntax.Markup as Markup
import qualified Data.Syntax as Syntax
import GHC.Stack
import qualified Language.Markdown as Grammar (Grammar(..))
import Prologue hiding (Location, link, list)
import qualified Term

type Syntax =
  '[ Markup.Document
   -- Block elements
   , Markup.Heading
   , Markup.OrderedList
   , Markup.Paragraph
   , Markup.UnorderedList
   -- Inline elements
   , Markup.Emphasis
   , Markup.Link
   , Markup.Strong
   , Markup.Text
   -- Assignment errors; cmark does not provide parse errors.
   , Syntax.Error Error
   ]

type Error = Assignment.Error Grammar.Grammar
type Term = Term.Term (Union Syntax) (Record Location)
type Assignment = HasCallStack => Assignment.Assignment (Cofree [] (Record (CMark.NodeType ': Location))) Grammar.Grammar Term


assignment :: Assignment
assignment = makeTerm <$> symbol Grammar.Document <*> children (Markup.Document <$> many blockElement)


-- Block elements

blockElement :: Assignment
blockElement = paragraph <|> list <|> heading

paragraph :: Assignment
paragraph = makeTerm <$> symbol Grammar.Paragraph <*> children (Markup.Paragraph <$> many inlineElement)

list :: Assignment
list = (cofree .) . (:<) <$> symbol Grammar.List <*> (project (\ (((CMark.LIST CMark.ListAttributes{..}) :. _) :< _) -> case listType of
  CMark.BULLET_LIST -> inj . Markup.UnorderedList
  CMark.ORDERED_LIST -> inj . Markup.OrderedList) <*> children (many item))

item :: Assignment
item = symbol Grammar.Item *> children blockElement

heading :: Assignment
heading = makeTerm <$> symbol Grammar.Heading <*> (Markup.Heading <$> project (\ ((CMark.HEADING level :. _) :< _) -> level) <*> children (many inlineElement))


-- Inline elements

inlineElement :: Assignment
inlineElement = strong <|> emphasis <|> text <|> link

strong :: Assignment
strong = makeTerm <$> symbol Grammar.Strong <*> children (Markup.Strong <$> many inlineElement)

emphasis :: Assignment
emphasis = makeTerm <$> symbol Grammar.Emphasis <*> children (Markup.Emphasis <$> many inlineElement)

text :: Assignment
text = makeTerm <$> symbol Grammar.Text <*> (Markup.Text <$> source)

link :: Assignment
link = makeTerm <$> symbol Grammar.Link <*> (uncurry Markup.Link <$> project (\ (((CMark.LINK url title) :. _) :< _) -> (toS url, toS title))) <* source


-- Implementation details

makeTerm :: (InUnion fs f, HasCallStack) => a -> f (Term.Term (Union fs) a) -> Term.Term (Union fs) a
makeTerm a f = cofree $ a :< inj f
