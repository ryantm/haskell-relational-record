{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}

-- |
-- Module      : Database.Relational.Query.Component
-- Copyright   : 2013 Kei Hibino
-- License     : BSD3
--
-- Maintainer  : ex8k.hibino@gmail.com
-- Stability   : experimental
-- Portability : unknown
--
-- This module provides untyped components for query.
module Database.Relational.Query.Component
       ( -- * Type for column SQL string
         ColumnSQL, columnSQL, columnSQL', showsColumnSQL,

         -- * Configuration type for query
         NameConfig (..),
         SchemaNameMode (..),
         Config ( productUnitSupport
                , chunksInsertSize
                , schemaNameMode
                , normalizedTableName
                , verboseAsCompilerWarning
                , nameConfig),
         defaultConfig,
         ProductUnitSupport (..), Duplication (..),

         -- * Duplication attribute
         showsDuplication,

         -- * Types for aggregation
         AggregateColumnRef,

         AggregateBitKey, AggregateSet, AggregateElem,

         aggregateColumnRef, aggregateEmpty,
         aggregatePowerKey, aggregateGroupingSet,
         aggregateRollup, aggregateCube, aggregateSets,

         composeGroupBy, composePartitionBy,

         AggregateKey, aggregateKeyProjection, aggregateKeyElement, unsafeAggregateKey,

         -- * Types for ordering
         Order (..), OrderColumn, OrderingTerm, OrderingTerms,
         composeOrderBy,

         -- * Types for assignments
         AssignColumn, AssignTerm, Assignment, Assignments, composeSets, composeValues,

         -- * Compose window clause
         composeOver,
       ) where

import Data.Monoid (Monoid (..), (<>))

import Database.Relational.Query.Internal.SQL (StringSQL, stringSQL, showStringSQL, rowConsStringSQL)
import Language.SQL.Keyword (Keyword(..), (|*|), (.=.))

import qualified Language.SQL.Keyword as SQL
import Language.Haskell.TH.Name.CamelCase (VarName, varCamelcaseName)
import qualified Database.Record.TH as RecordTH


-- | Simple wrap type
newtype ColumnSQL' a = ColumnSQL a

instance Functor ColumnSQL' where
  fmap f (ColumnSQL c) = ColumnSQL $ f c

-- | Column SQL string type
type ColumnSQL = ColumnSQL' StringSQL

-- | 'ColumnSQL' from string
columnSQL :: String -> ColumnSQL
columnSQL =  columnSQL' . stringSQL

-- | 'ColumnSQL' from 'StringSQL'
columnSQL' :: StringSQL -> ColumnSQL
columnSQL' =  ColumnSQL

-- | String from ColumnSQL
stringFromColumnSQL :: ColumnSQL -> String
stringFromColumnSQL =  showStringSQL . showsColumnSQL

-- | StringSQL from ColumnSQL
showsColumnSQL :: ColumnSQL -> StringSQL
showsColumnSQL (ColumnSQL c) = c

instance Show ColumnSQL where
  show = stringFromColumnSQL

-- | 'NameConfig' type to customize names of expanded templates.
data NameConfig =
  NameConfig
  { recordConfig       ::  RecordTH.NameConfig
  , relationVarName    ::  String -> String -> VarName
  , overloadedRecords  :: Bool
  }

instance Show NameConfig where
  show = const "<NameConfig>"

-- | Schema name qualify mode in SQL string.
data SchemaNameMode
  = SchemaQualified     -- ^ Schema qualified table name in SQL string
  | SchemaNotQualified  -- ^ Not qualified table name in SQL string
  deriving (Eq, Show)

-- | Configuration type.
data Config =
  Config
  { productUnitSupport        ::  !ProductUnitSupport
  , chunksInsertSize          ::  !Int
  , schemaNameMode            ::  !SchemaNameMode
  , normalizedTableName       ::  !Bool
  , verboseAsCompilerWarning  ::  !Bool
  , nameConfig                ::  !NameConfig
  } deriving Show

-- | Default configuration.
defaultConfig :: Config
defaultConfig =
  Config { productUnitSupport        =  PUSupported
         , chunksInsertSize          =  256
         , schemaNameMode            =  SchemaQualified
         , normalizedTableName       =  True
         , verboseAsCompilerWarning  =  False
         , nameConfig                =  NameConfig { recordConfig     =  RecordTH.defaultNameConfig
                                                   , relationVarName  =  const varCamelcaseName
                                                   , overloadedRecords = False
                                                   }
         }

-- | Unit of product is supported or not.
data ProductUnitSupport = PUSupported | PUNotSupported  deriving Show


-- | Result record duplication attribute
data Duplication = All | Distinct  deriving Show

-- | Compose duplication attribute string.
showsDuplication :: Duplication -> StringSQL
showsDuplication =  dup  where
  dup All      = ALL
  dup Distinct = DISTINCT


-- | Type for group-by term
type AggregateColumnRef = ColumnSQL

-- | Type for group key.
newtype AggregateBitKey = AggregateBitKey [AggregateColumnRef] deriving Show

-- | Type for grouping set
newtype AggregateSet = AggregateSet [AggregateElem] deriving Show

-- | Type for group-by tree
data AggregateElem = ColumnRef AggregateColumnRef
                   | Rollup [AggregateBitKey]
                   | Cube   [AggregateBitKey]
                   | GroupingSets [AggregateSet]
                   deriving Show

-- | Single term aggregation element.
aggregateColumnRef :: AggregateColumnRef -> AggregateElem
aggregateColumnRef =  ColumnRef

-- | Key of aggregation power set.
aggregatePowerKey :: [AggregateColumnRef] -> AggregateBitKey
aggregatePowerKey =  AggregateBitKey

-- | Single grouping set.
aggregateGroupingSet :: [AggregateElem] -> AggregateSet
aggregateGroupingSet =  AggregateSet

-- | Rollup aggregation element.
aggregateRollup :: [AggregateBitKey] -> AggregateElem
aggregateRollup =  Rollup

-- | Cube aggregation element.
aggregateCube :: [AggregateBitKey] -> AggregateElem
aggregateCube =  Cube

-- | Grouping sets aggregation.
aggregateSets :: [AggregateSet] -> AggregateElem
aggregateSets =  GroupingSets

-- | Empty aggregation.
aggregateEmpty :: [AggregateElem]
aggregateEmpty =  []

showsAggregateColumnRef :: AggregateColumnRef -> StringSQL
showsAggregateColumnRef =  showsColumnSQL

commaed :: [StringSQL] -> StringSQL
commaed =  SQL.fold (|*|)

pComma :: (a -> StringSQL) -> [a] -> StringSQL
pComma qshow =  SQL.paren . commaed . map qshow

showsAggregateBitKey :: AggregateBitKey -> StringSQL
showsAggregateBitKey (AggregateBitKey ts) = pComma showsAggregateColumnRef ts

-- | Compose GROUP BY clause from AggregateElem list.
composeGroupBy :: [AggregateElem] -> StringSQL
composeGroupBy =  d where
  d []       = mempty
  d es@(_:_) = GROUP <> BY <> rec es
  keyList op ss = op <> pComma showsAggregateBitKey ss
  rec = commaed . map showsE
  showsGs (AggregateSet s) = SQL.paren $ rec s
  showsE (ColumnRef t)     = showsAggregateColumnRef t
  showsE (Rollup ss)       = keyList ROLLUP ss
  showsE (Cube   ss)       = keyList CUBE   ss
  showsE (GroupingSets ss) = GROUPING <> SETS <> pComma showsGs ss

-- | Compose PARTITION BY clause from AggregateColumnRef list.
composePartitionBy :: [AggregateColumnRef] -> StringSQL
composePartitionBy =  d where
  d []       = mempty
  d ts@(_:_) = PARTITION <> BY <> commaed (map showsAggregateColumnRef ts)

-- | Typeful aggregate element.
newtype AggregateKey a = AggregateKey (a, AggregateElem)

-- | Extract typed projection from 'AggregateKey'.
aggregateKeyProjection :: AggregateKey a -> a
aggregateKeyProjection (AggregateKey (p, _c)) = p

-- | Extract untyped term from 'AggregateKey'.
aggregateKeyElement :: AggregateKey a -> AggregateElem
aggregateKeyElement (AggregateKey (_p, c)) = c

-- | Unsafely bind typed-projection and untyped-term into 'AggregateKey'.
unsafeAggregateKey :: (a, AggregateElem) -> AggregateKey a
unsafeAggregateKey = AggregateKey


-- | Order direction. Ascendant or Descendant.
data Order = Asc | Desc  deriving Show

-- | Type for order-by column
type OrderColumn = ColumnSQL

-- | Type for order-by term
type OrderingTerm = (Order, OrderColumn)

-- | Type for order-by terms
type OrderingTerms = [OrderingTerm]

-- | Compose ORDER BY clause from OrderingTerms
composeOrderBy :: OrderingTerms -> StringSQL
composeOrderBy =  d where
  d []       = mempty
  d ts@(_:_) = ORDER <> BY <> commaed (map showsOt ts)
  showsOt (o, e) = showsColumnSQL e <> order o
  order Asc  = ASC
  order Desc = DESC


-- | Column SQL String
type AssignColumn = ColumnSQL

-- | Value SQL String
type AssignTerm   = ColumnSQL

-- | Assignment pair
type Assignment = (AssignColumn, AssignTerm)

-- | Assignment pair list.
type Assignments = [Assignment]

-- | Compose SET clause from 'Assignments'.
composeSets :: Assignments -> StringSQL
composeSets as = assigns  where
  assignList = foldr (\ (col, term) r ->
                       (showsColumnSQL col .=. showsColumnSQL term) : r)
               [] as
  assigns | null assignList = error "Update assignment list is null!"
          | otherwise       = SET <> commaed assignList

-- | Compose VALUES clause from 'Assignments'.
composeValues :: Assignments -> StringSQL
composeValues as = rowConsStringSQL [ showsColumnSQL c | c <- cs ] <> VALUES <>
                   rowConsStringSQL [ showsColumnSQL c | c <- vs ]  where
  (cs, vs) = unzip as


-- | Compose /OVER (PARTITION BY ... )/ clause.
composeOver :: [AggregateColumnRef] -> OrderingTerms -> StringSQL
composeOver pts ots =
  OVER <> SQL.paren (composePartitionBy pts <> composeOrderBy ots)
