#pragma once

#include <atomic>
#include <functional>
#include <utility>

// Off-audio-thread cooperative cancellation. A callback also permits deterministic
// regression checks that cancel after work has entered a particular CPU loop.
class AnalysisCancellation
{
public:
    AnalysisCancellation() = default;
    AnalysisCancellation (const std::atomic<bool>& flag) : check ([&flag] { return flag.load(); }) {}
    AnalysisCancellation (std::function<bool()> callback) : check (std::move (callback)) {}
    explicit operator bool() const { return check && check(); }

private:
    std::function<bool()> check;
};
