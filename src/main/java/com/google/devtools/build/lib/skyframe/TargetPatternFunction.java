// Copyright 2014 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
package com.google.devtools.build.lib.skyframe;

import com.google.common.collect.ImmutableSet;
import com.google.common.collect.Iterables;
import com.google.common.util.concurrent.MoreExecutors;
import com.google.devtools.build.lib.cmdline.Label;
import com.google.devtools.build.lib.cmdline.ResolvedTargets;
import com.google.devtools.build.lib.cmdline.TargetParsingException;
import com.google.devtools.build.lib.cmdline.TargetPattern;
import com.google.devtools.build.lib.collect.CompactHashSet;
import com.google.devtools.build.lib.packages.Target;
import com.google.devtools.build.lib.skyframe.EnvironmentBackedRecursivePackageProvider.MissingDepException;
import com.google.devtools.build.lib.util.BatchCallback;
import com.google.devtools.build.lib.util.Preconditions;
import com.google.devtools.build.lib.vfs.PathFragment;
import com.google.devtools.build.skyframe.SkyFunction;
import com.google.devtools.build.skyframe.SkyFunctionException;
import com.google.devtools.build.skyframe.SkyKey;
import com.google.devtools.build.skyframe.SkyValue;

import java.util.Set;

import javax.annotation.Nullable;

/**
 * TargetPatternFunction translates a target pattern (eg, "foo/...") into a set of resolved
 * Targets.
 */
public class TargetPatternFunction implements SkyFunction {

  public TargetPatternFunction() {
  }

  @Override
  public SkyValue compute(SkyKey key, Environment env) throws TargetPatternFunctionException,
      InterruptedException {
    TargetPatternValue.TargetPatternKey patternKey =
        ((TargetPatternValue.TargetPatternKey) key.argument());
    ResolvedTargets<Target> resolvedTargets;
    try {
      EnvironmentBackedRecursivePackageProvider provider =
          new EnvironmentBackedRecursivePackageProvider(env);
      RecursivePackageProviderBackedTargetPatternResolver resolver =
          new RecursivePackageProviderBackedTargetPatternResolver(provider, env.getListener(),
              patternKey.getPolicy(), MoreExecutors.newDirectExecutorService());
      TargetPattern parsedPattern = patternKey.getParsedPattern();
      ImmutableSet<PathFragment> excludedSubdirectories = patternKey.getExcludedSubdirectories();
      final Set<Target> results = CompactHashSet.create();
      BatchCallback<Target, RuntimeException> callback =
          new BatchCallback<Target, RuntimeException>() {
            @Override
            public void process(Iterable<Target> partialResult) {
              Iterables.addAll(results, partialResult);
            }
          };
      parsedPattern.eval(resolver, excludedSubdirectories, callback, RuntimeException.class);
      resolvedTargets = ResolvedTargets.<Target>builder().addAll(results).build();
    } catch (TargetParsingException e) {
      throw new TargetPatternFunctionException(e);
    } catch (MissingDepException e) {
      // The EnvironmentBackedRecursivePackageProvider constructed above might throw
      // MissingDepException to signal when it has a dependency on a missing Environment value.
      // Note that MissingDepException extends RuntimeException because the methods called
      // on EnvironmentBackedRecursivePackageProvider all belong to an interface shared with other
      // implementations that are unconcerned with MissingDepExceptions.
      return null;
    }
    Preconditions.checkNotNull(resolvedTargets, key);
    ResolvedTargets.Builder<Label> resolvedLabelsBuilder = ResolvedTargets.builder();
    for (Target target : resolvedTargets.getTargets()) {
      resolvedLabelsBuilder.add(target.getLabel());
    }
    for (Target target : resolvedTargets.getFilteredTargets()) {
      resolvedLabelsBuilder.remove(target.getLabel());
    }
    return new TargetPatternValue(resolvedLabelsBuilder.build());
  }

  @Nullable
  @Override
  public String extractTag(SkyKey skyKey) {
    return null;
  }

  /**
   * Used to declare all the exception types that can be wrapped in the exception thrown by
   * {@link TargetPatternFunction#compute}.
   */
  private static final class TargetPatternFunctionException extends SkyFunctionException {
    public TargetPatternFunctionException(TargetParsingException e) {
      super(e, Transience.PERSISTENT);
    }
  }
}
